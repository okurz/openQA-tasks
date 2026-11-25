# Detailed Execution Plan: Migrate from timeago to timeago.js

## Background

- **Issue:** The `timeago` library declares `"jquery": ">=1.5.0 <4.0"` in its `package.json`, making it officially incompatible with jQuery 4.0.0.
- **Current state:** openQA uses jQuery shims to maintain compatibility with `timeago`, but this is a fragile dependency.
- **Goal:** Replace `timeago` (jQuery plugin) with `timeago.js` (hustcc version) - a vanilla JavaScript library with no jQuery dependency.
- **Reference:** [timeago.js GitHub](https://github.com/hustcc/timeago.js)

## Why timeago.js?

- **Vanilla JS**: No jQuery dependency
- **Tiny**: ~2 KB
- **Popular**: 5,300+ stars, well-maintained
- **i18n**: Supports 60+ languages
- **Drop-in conceptually**: Similar API to current usage

## Current timeago Usage in openQA

### 1. jQuery Plugin Initialization (5 occurrences)

These files use `$('.timeago').timeago()` or similar jQuery plugin pattern:

- **`assets/javascripts/running.js`**
  - Line 403: `infoBoxJQuery.find('.timeago').timeago();`
  - Line 759: `timeagoElement.timeago();`

- **`assets/javascripts/overview.js`**
  - Line 125: `$('.timeago').timeago();`

- **`assets/javascripts/index.js`**
  - Line 93: `$('.timeago').timeago();`

- **`assets/javascripts/comments.js`**
  - Line 19: `abbr.timeago();`

### 2. Programmatic Usage (7 occurrences)

These files call `jQuery.timeago()` or `$.timeago()` directly:

- **`assets/javascripts/openqa.js`**
  - Line 452: `timeago.textContent = jQuery.timeago(job.t_finished);`

- **`assets/javascripts/tests.js`**
  - Line 125: `jQuery.timeago(data)`

- **`assets/javascripts/job_next_previous.js`**
  - Line 151: `jQuery.timeago(data)`

- **`assets/javascripts/audit_log.js`**
  - Line 120: `jQuery.timeago(data + ' UTC')`
  - Line 360: `jQuery.timeago(data + 'Z')`

- **`assets/javascripts/admin_needle.js`**
  - Line 33: `jQuery.timeago(new Date(data))`

### 3. Dependencies

- **`package.json`**: `timeago: ^1.6.7`
- **`assetpack.def`**: Line ~128 loads `../node_modules/timeago/jquery.timeago.js`

## Migration Steps

### Phase 1: Preparation

1. **Install timeago.js**

   ```bash
   npm install timeago.js --save
   ```

2. **Update `package.json`**
   - Remove: `"timeago": "^1.6.7"`
   - Add: `"timeago.js": "^4.0.2"`

3. **Update `assetpack.def`**
   - Remove: `< ../node_modules/timeago/jquery.timeago.js`
   - Add: `< ../node_modules/timeago.js/dist/timeago.min.js`

### Phase 2: Code Changes

#### Step 2.1: Replace jQuery plugin initialization

The jQuery plugin pattern `$('.timeago').timeago()` must be replaced with the timeago.js initialization.

**Before (jQuery plugin):**

```javascript
$('.timeago').timeago();
```

**After (timeago.js):**

```javascript
import timeago from 'timeago.js';
const timeagoInstance = timeago();
timeagoInstance.render(document.querySelectorAll('.timeago'));
```

Or using the global:

```javascript
timeago.render(document.querySelectorAll('.timeago'));
```

**Files to update:**

| File          | Line | Current Code                                | New Code                                                 |
| ------------- | ---- | ------------------------------------------- | -------------------------------------------------------- |
| `running.js`  | 403  | `infoBoxJQuery.find('.timeago').timeago();` | `timeago.render(infoBoxJQuery.find('.timeago').get());`  |
| `running.js`  | 759  | `timeagoElement.timeago();`                 | `timeago.render(timeagoElement.get());`                  |
| `overview.js` | 125  | `$('.timeago').timeago();`                  | `timeago.render(document.querySelectorAll('.timeago'));` |
| `index.js`    | 93   | `$('.timeago').timeago();`                  | `timeago.render(document.querySelectorAll('.timeago'));` |
| `comments.js` | 19   | `abbr.timeago();`                           | `timeago.render(abbr.get());`                            |

#### Step 2.2: Replace programmatic `$.timeago()` calls

**Before:**

```javascript
jQuery.timeago(dateString);
```

**After:**

```javascript
timeago.format(dateString);
```

**Files to update:**

| File                   | Line | Current Code                     | New Code                         |
| ---------------------- | ---- | -------------------------------- | -------------------------------- |
| `openqa.js`            | 452  | `jQuery.timeago(job.t_finished)` | `timeago.format(job.t_finished)` |
| `tests.js`             | 125  | `jQuery.timeago(data)`           | `timeago.format(data)`           |
| `job_next_previous.js` | 151  | `jQuery.timeago(data)`           | `timeago.format(data)`           |
| `audit_log.js`         | 120  | `jQuery.timeago(data + ' UTC')`  | `timeago.format(data + ' UTC')`  |
| `audit_log.js`         | 360  | `jQuery.timeago(data + 'Z')`     | `timeago.format(data + 'Z')`     |
| `admin_needle.js`      | 33   | `jQuery.timeago(new Date(data))` | `timeago.format(new Date(data))` |

#### Step 2.3: Remove jQuery shims

After migration, the following shims in `openqa.js` are no longer needed for timeago:

- `$.trim` - still needed for chosen.js
- `$.isFunction` - **CAN BE REMOVED** (was only for timeago)
- `$.inArray` - still needed for chosen.js

Remove the comment about timeago incompatibility and update the `$.isFunction` comment.

### Phase 3: Testing

1. **Lint**: Run `npm run lint` and `make jshint`
2. **Unit tests**: Check for any timeago-related tests
3. **UI tests**: Run `make test-ui`
4. **Manual verification**: Check that relative timestamps display correctly on:
   - Job list/overview pages
   - Test result pages
   - Comments
   - Running test info
   - Audit log

### Phase 4: Cleanup

1. Remove unused timeago shim comments from `openqa.js`
2. Verify `$.isFunction` is still needed (check chosen.js usage)
3. Update this task file as completed

## Key Differences to Handle

### 1. Date Format Handling

timeago.js accepts:

- ISO 8601 strings: `timeago.format('2024-01-15T12:30:00Z')`
- Date objects: `timeago.format(new Date())`
- Unix timestamps (ms): `timeago.format(1705329000000)`

Current code passes:

- ISO strings: `jQuery.timeago('2024-01-15T12:30:00Z')` ✓
- Date objects: `jQuery.timeago(new Date(data))` ✓
- Some code adds `' UTC'` or `'Z'` suffix - may not be needed with timeago.js

### 2. Auto-updates

jQuery timeago plugin automatically updates elements. timeago.js also supports this:

- `timeago.render(elements)` - renders and sets up auto-update (default: every 60s)
- To change interval: `timeago({ interval: 30 * 1000 }).render(elements)`

### 3. Localization

timeago.js uses `timeago.locales[key]` for translations. Default is English.

- Add locales via: `import 'timeago.js/dist/timeago_locale/zh-CN.js'`
- Use: `timeago.format(date, 'zh-CN')`

No localization changes expected for initial migration.

## Rollback Plan

If issues occur:

1. Revert `package.json` and `assetpack.def` changes
2. Restore removed shims in `openqa.js`
3. Revert all programmatic and initialization changes
4. Re-run tests

## Estimated Effort

- **Preparation**: 10 min
- **Code changes**: 30-45 min
- **Testing**: 30 min
- **Total**: ~1.5 hours

## References

- [timeago.js GitHub](https://github.com/hustcc/timeago.js)
- [timeago.js CDN](https://cdn.jsdelivr.net/npm/timeago.js@4.0.2/dist/timeago.min.js)
- [jQuery timeago](https://github.com/pragma/http-status) (current)
