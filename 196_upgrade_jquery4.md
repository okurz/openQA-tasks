# Detailed Execution Plan: Upgrading to jQuery 4.0.0

## Background

- **PR:** [#6984](https://github.com/os-autoinst/openQA/pull/6984)
- **Goal:** Adapt `openQA`'s JavaScript codebase to fix UI, fullstack, and unstable CI jobs failing after `dependabot` bumped the `jquery` dependency from `3.7.1` to `4.0.0`.
- **References:** [jQuery 4.0 Upgrade Guide](https://jquery.com/upgrade-guide/4.0/#start-here-if-currently-using-jquery-3-x)

## Identified Breaking Changes and Required Code Adaptations

Based on the migration guide and a static analysis of the repository, the following adaptations are required:

### 1. Replace Deprecated `$.trim()` and `jQuery.trim()`

jQuery 4.0 completely removes the `jQuery.trim` method. We must replace it with the native JavaScript `String.prototype.trim()` function.

- **`assets/javascripts/admin_user.js`**
  - **Line 20**:
    - _From:_ `if (!confirm('Are you sure to put ' + username + ' into role: ' + $.trim(role) + '?')) {`
    - _To:_ `if (!confirm('Are you sure to put ' + username + ' into role: ' + role.trim() + '?')) {`

- **`assets/javascripts/admin_groups.js`**
  - **Line 61**:
    - _From:_ `(count, e) => count + (e.type !== 'number' && !jQuery.trim(e.value).length),`
    - _To:_ `(count, e) => count + (e.type !== 'number' && !e.value.trim().length),`
  - **Line 77**:
    - _From:_ `if (!jQuery.trim(this.value).length) {`
    - _To:_ `if (!this.value.trim().length) {`

### 2. Explicitly Append `'px'` to Unitless CSS Properties

jQuery 4.0 stops automatically appending `'px'` to most CSS property values passed via `.css()`. Properties like `margin-bottom`, `left`, `top`, `width`, and `height` must now explicitly specify their units if they are being mathematically calculated as unitless numbers.

- **`assets/javascripts/test_result.js`**
  - **Line 97**:
    - _From:_ `rrow.css('margin-bottom', endOfPreview - endOfRow + extraMargin);`
    - _To:_ `rrow.css('margin-bottom', (endOfPreview - endOfRow + extraMargin) + 'px');`
  - **Line 126**:
    - _From:_ `pin.css('left', -($('.result').width() + $('.component').width() + 2 * 16));`
    - _To:_ `pin.css('left', -($('.result').width() + $('.component').width() + 2 * 16) + 'px');`

- **`assets/3rdparty/bootstrap-4-multi-dropdown-navbar/beta2.0/js/bootstrap-4-navbar.js`**
  - **Line 26**:
    - _From:_ `$el.next().css( { "top": $el[0].offsetTop, "left": $parent.outerWidth() - 4 } );`
    - _To:_ `$el.next().css( { "top": $el[0].offsetTop + 'px', "left": ($parent.outerWidth() - 4) + 'px' } );`
      _(Note: Updating vendored 3rd-party scripts is usually discouraged, but may be necessary here if a patched upstream version doesn't exist yet.)_

### 3. Replace Invalid Usage of `css()` with Object Literal or `attr('style')`

In older versions of jQuery, passing an entire raw CSS string as the first parameter to `.css()` might fail silently or fall back to browser parsing quirks. In jQuery 4.0, this should be corrected to properly configure styles.

- **`assets/javascripts/needlediff.js`**
  - **Lines 42-44**:
    - _From:_
      ```javascript
      container.css(
        'border: 1px solid black; margin: 0px; position: relative; width: ' + width + 'px; height: ' + height + 'px;'
      );
      ```
    - _To:_
      ```javascript
      container.css({
        border: '1px solid black',
        margin: '0px',
        position: 'relative',
        width: width + 'px',
        height: height + 'px'
      });
      ```

## Execution Steps

1. **Apply JavaScript Code Fixes**: Manually edit the mentioned 4 JS files to incorporate the changes described above.
2. **Lint JavaScript Code**: Run `make jshint` and `npm run lint` locally to make sure the rewritten logic adheres to openQA's ESLint standards.
3. **Verify Functionality**:
   - Make sure `dependabot`'s package updates are applied locally (`npm install jquery@4.0.0`).
   - Run the local UI tests: `make test-ui`
   - Run fullstack tests if possible.
4. **Commit & Push**:
   - Create a single commit capturing all the deprecation fixes with an appropriate descriptive multi-line commit message.
   - Do NOT push but inform the user
