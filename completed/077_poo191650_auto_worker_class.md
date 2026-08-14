# Task 077: Automatically Add Configurable Worker Class to Jobs

**Redmine Ticket**: https://progress.opensuse.org/issues/191650  
**Task Number**: 077  
**Task ID**: `poo191650`  
**Description**: `auto_worker_class`  
**Task Name**: `077_poo191650_auto_worker_class`  
**Branch**: `feature/077_poo191650_auto_worker_class`

## Motivation

To prevent overloading workers, openQA uses worker size classes (e.g., `size-small`, `size-medium`, `size-large`) as documented in https://gitlab.<internal>/openqa/salt-pillars-openqa/#worker-classes. Currently, these must be added explicitly to jobs. This task implements automatic worker class assignment based on instance-specific configuration, allowing administrators to specify default size classes for jobs that don't already have them.

## Acceptance Criteria

- **AC1**: Given according configuration exists, openQA automatically adds worker class to jobs missing the specified class pattern
- **AC2**: By default (no configuration), openQA does not automatically add any worker class settings

---

## Analysis Summary

### Current State

From codebase exploration:

1. **Worker Classes**: 
   - Defined via `WORKER_CLASS` parameter in job settings
   - Can be set on machines, products, test suites, job templates
   - Multiple classes are sorted and comma-joined (e.g., `qemu_x86_64,size-large`)
   
2. **Job Creation**: 
   - `lib/OpenQA/Schema/ResultSet/Jobs.pm::create_from_settings()` (line ~145)
   - Assigns default `qemu_<ARCH>` if WORKER_CLASS not specified
   
3. **Configuration**: 
   - openQA uses `openqa.ini` for web UI settings
   - Parsed by `lib/OpenQA/Config.pm` using `Config::IniFiles`
   
4. **Scheduler Matching**:
   - Uses AND logic: workers must have ALL specified classes
   - Implemented in `lib/OpenQA/Scheduler/Model/Jobs.pm::_matching_workers()`

### Design Decisions

**Configuration Format** (in `openqa.ini`):
```ini
[worker_class_auto_assignment]
add_worker_class_if_missing = size-.* -> size-large
add_worker_class_if_missing = gpu-.* -> gpu-none
```

**Behavior**:
- **Global configuration only** (scope limited to main `openqa.ini` for simplicity)
- **Add all non-matching patterns**: If job lacks both `size-*` and `gpu-*`, add both defaults
- **Log at INFO level**: When auto-assignment occurs (for visibility/debugging)
- **Resilient error handling**: Log warning and skip invalid regex patterns (don't fail service startup)

**Logic Flow**:
1. Parse configuration from `openqa.ini` section `[worker_class_auto_assignment]`
2. During job creation in `create_from_settings()`, after WORKER_CLASS collection
3. For each configured pattern:
   - Split existing WORKER_CLASS by comma
   - Check if ANY class matches the pattern regex
   - If NO match found, append the configured default class
4. Sort and join classes (maintain existing behavior)

## Implementation Plan

### Phase 1: Test-Driven Development (Start with Tests)

#### Step 1.1: Add tests to `t/05-scheduler-capabilities.t`

**Test scenarios** (integration level):
- Job without `size-*` class + config exists → job gets `size-large`
- Job with existing `size-small` + config exists → job keeps `size-small` (not modified)
- Job without config → unchanged (AC2 - backward compatibility)
- Full scheduler flow: job with auto-assigned class matches worker with that class
- Job with auto-assigned class does NOT match worker without that class

**Implementation approach**:
- Add test configuration file in `t/data/` with auto-assignment rules
- Create test jobs with various WORKER_CLASS configurations
- Register workers with different size classes
- Verify scheduler matches correctly
- Expected: Tests FAIL initially (TDD approach)

#### Step 1.2: Add tests to `t/40-job_settings.t`

**Test scenarios** (unit level):
- Configuration parsing: valid format → returns correct array of rules
- Configuration parsing: invalid regex → logs warning, skips entry
- Configuration parsing: empty section → returns empty array (AC2)
- Pattern matching: job with `qemu_x86_64` missing `size-*` → add `size-large`
- Pattern matching: job with `qemu_x86_64,size-small` has `size-*` → no change
- Multiple patterns: job missing both `size-*` and `gpu-*` → add both defaults
- Edge case: empty WORKER_CLASS → auto-assignment works
- Edge case: malformed config line → skip gracefully

**Expected**: Tests FAIL initially (TDD)

### Phase 2: Configuration Parser Implementation

#### Step 2.1: Add configuration parsing function

**Location**: `lib/OpenQA/Config.pm` (extend existing module)

**Function signature**:
```perl
sub parse_worker_class_auto_assignment {
    my ($config_hash) = @_;  # Config::IniFiles object or hash
    return \@rules;  # Array of {pattern => qr/regex/, class => 'default-class'}
}
```

**Implementation details**:
- Read `worker_class_auto_assignment` section from config
- Parse each `add_worker_class_if_missing = <regex> -> <class>` line
- Split on ` -> ` delimiter
- Compile regex pattern using `qr/.../`
- Handle errors:
  - Invalid regex: `log_warning` and skip entry
  - Missing delimiter: `log_warning` and skip entry
  - Empty value: skip entry
- Return array reference of hash references

**Error handling**:
```perl
eval { $pattern_regex = qr/$pattern_str/ };
if ($@) {
    log_warning("Invalid regex pattern in worker_class_auto_assignment: $pattern_str");
    next;
}
```

#### Step 2.2: Unit tests for configuration parser

Add to `t/40-job_settings.t` or new test file `t/40-config.t`:
- Test valid configuration returns correct data structure
- Test invalid regex is skipped with warning
- Test missing section returns empty array
- Test multiple rules are all returned

### Phase 3: Job Creation Enhancement

#### Step 3.1: Modify `lib/OpenQA/Schema/ResultSet/Jobs.pm`

**Location**: `create_from_settings()` function, after line ~145

**Implementation**:
```perl
# After WORKER_CLASS is collected from settings
my $worker_class = $settings->{WORKER_CLASS} // '';

# Load auto-assignment configuration (cache for performance)
state $auto_assignment_rules = _load_auto_assignment_config();

# Apply auto-assignment rules
if (@$auto_assignment_rules) {
    my @existing_classes = split(',', $worker_class);
    my @classes_to_add;
    
    for my $rule (@$auto_assignment_rules) {
        my $pattern = $rule->{pattern};
        my $has_match = grep { $_ =~ $pattern } @existing_classes;
        
        unless ($has_match) {
            push @classes_to_add, $rule->{class};
            log_info("Auto-assigning worker class '$rule->{class}' to job (no match for pattern '$pattern')");
        }
    }
    
    if (@classes_to_add) {
        push @existing_classes, @classes_to_add;
        $worker_class = join(',', sort @existing_classes);
        $settings->{WORKER_CLASS} = $worker_class;
    }
}

# Continue with existing logic...
```

**Helper function**:
```perl
sub _load_auto_assignment_config {
    my $config = OpenQA::App->singleton->config;
    return OpenQA::Config::parse_worker_class_auto_assignment($config);
}
```

**Caching strategy**:
- Use `state` variable to cache parsed config (loaded once per process)
- Performance: avoid re-parsing config on every job creation
- Trade-off: requires service restart to pick up config changes (acceptable)

#### Step 3.2: Preserve existing behavior

**Critical requirements**:
- Sort classes alphabetically (existing behavior)
- Join with comma separator (existing behavior)
- Don't break chained dependencies (line 264-278 logic)
- Default `qemu_<ARCH>` still applies if no WORKER_CLASS specified

### Phase 4: Integration Testing

#### Step 4.1: Run Phase 1 tests

Execute:
```bash
make test-unit-and-integration TESTS=t/05-scheduler-capabilities.t
make test-unit-and-integration TESTS=t/40-job_settings.t
```

**Expected**: Tests now PASS (implementation complete)

#### Step 4.2: Extended integration scenarios

Add to `t/05-scheduler-capabilities.t`:
- Multiple workers with different size classes competing for jobs
- Priority handling with auto-assigned classes
- Jobs with no matching workers remain unassigned (existing behavior)

#### Step 4.3: Regression testing

Run full test suite:
```bash
make test-unit-and-integration
```

**Expected**: No regressions, all existing tests pass

### Phase 5: Code Quality & Verification

#### Step 5.1: Code style

Run:
```bash
make tidy
```

**Expected**: No changes needed (code follows style guide)

If changes made, review and commit them separately before proceeding.

#### Step 5.2: Static analysis

Run:
```bash
make test-checkstyle
```

**Expected**: All checks pass

Fix any issues:
- perlcritic violations
- eslint/prettier issues (if any JS touched)

#### Step 5.3: Coverage verification

Run targeted coverage:
```bash
make coverage TESTS="t/05-scheduler-capabilities.t t/40-job_settings.t"
```

**Goal**: 100% statement coverage on new code
- Check `lib/OpenQA/Config.pm` new function
- Check `lib/OpenQA/Schema/ResultSet/Jobs.pm` modified section

If coverage gaps found, add tests to close them.

### Phase 6: Documentation (Optional)

Check if documentation update needed:
- `docs/` folder - look for configuration documentation files
- Search for existing `openqa.ini` documentation
- If found, add section explaining `[worker_class_auto_assignment]`

**Example documentation**:
```
## Automatic Worker Class Assignment

To automatically assign default worker classes to jobs that don't have them, 
configure the `[worker_class_auto_assignment]` section in `openqa.ini`:

[worker_class_auto_assignment]
add_worker_class_if_missing = size-.* -> size-large
add_worker_class_if_missing = gpu-.* -> gpu-none

Each rule specifies a regex pattern and a default class. If a job's WORKER_CLASS
doesn't contain any class matching the pattern, the default class is added.
```

## Files to Modify

### Core Implementation
- **`lib/OpenQA/Config.pm`**: Add `parse_worker_class_auto_assignment()` function
- **`lib/OpenQA/Schema/ResultSet/Jobs.pm`**: Modify `create_from_settings()` to apply auto-assignment

### Tests
- **`t/05-scheduler-capabilities.t`**: Add integration tests for scheduler matching with auto-assigned classes
- **`t/40-job_settings.t`**: Add unit tests for configuration parsing and pattern matching

### Test Data
- **`t/data/openqa.ini`** or **`t/data/05-scheduler-capabilities/openqa.ini`**: Add test configuration with auto-assignment rules

### Documentation (if applicable)
- **`docs/`**: Update configuration documentation (to be determined based on existing structure)

## Edge Cases & Considerations

### Handled in Implementation

1. **Multiple patterns**: Apply ALL non-matching patterns (add both `size-large` and `gpu-none` if neither matches)
2. **Invalid regex**: Log warning, skip pattern, continue with others
3. **Empty WORKER_CLASS**: Auto-assignment works (split on empty string = empty array)
4. **Performance**: Cache parsed config using `state` variable
5. **Backward compatibility**: No config = no auto-assignment (AC2)
6. **Chained dependencies**: Auto-assignment happens before dependency logic (won't interfere)

### Testing Required

1. **Empty config section**: Returns empty array, no auto-assignment
2. **Malformed config line**: Skipped with warning, other rules still apply
3. **Complex regex patterns**: Test with `size-(small|medium|large)`, `gpu-.*`, etc.
4. **Job with ALL needed classes**: No modification
5. **Job with SOME needed classes**: Only add missing ones
6. **Job with NO classes initially**: Add all configured defaults

## Testing Strategy

### Test Organization

**Unit Tests** (`t/40-job_settings.t`):
- Configuration parsing logic
- Pattern matching logic
- Error handling

**Integration Tests** (`t/05-scheduler-capabilities.t`):
- Job creation with auto-assignment
- Scheduler matching with auto-assigned classes
- Full workflow: config → job → worker matching

**Regression Tests** (existing test suite):
- Verify no behavior change without config (AC2)
- Verify existing WORKER_CLASS handling unchanged

### Coverage Goals

- **Target**: 100% statement coverage on new code
- **Method**: Run `make coverage` with targeted tests
- **Focus areas**:
  - `parse_worker_class_auto_assignment()` - all code paths
  - Auto-assignment block in `create_from_settings()` - all branches

## Success Criteria Checklist

- [ ] **AC1**: Jobs without matching class get auto-assigned class from config
- [ ] **AC2**: Without config, behavior unchanged (backward compatible)
- [ ] All new tests pass
- [ ] All existing tests pass (no regressions)
- [ ] `make tidy` passes
- [ ] `make test-checkstyle` passes
- [ ] Code coverage maintained/improved on modified files
- [ ] Configuration parsing handles invalid input gracefully
- [ ] Logging at INFO level when auto-assignment occurs
- [ ] Documentation updated (if applicable)

---
