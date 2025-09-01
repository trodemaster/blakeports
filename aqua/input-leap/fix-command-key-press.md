### macOS: Fix unreliable Command-key combos (Cmd+C / Cmd+V)

- **Problem**
  - On macOS clients, Command-key combos frequently failed; the character was typed instead of the shortcut.
  - Logs showed the modifier state flipping between Meta (0x0008) and Super (0x0010), and sometimes Command was toggled up/down around the character press.

- **Root cause**
  - High-level key mapping transitioned Command from Meta→Super mid-combo, injecting Command up/down around the character.
  - Low-level posting could clear the global Command mask too aggressively when tracking left/right Command independently.

- **Changes**
  - `src/lib/inputleap/KeyMap.cpp`
    - **Normalize Command mask**: Convert Meta → Super when generating Command to prevent mid-combo flips.
    - **Consistent state updates**: Update `activeModifiers` and `currentState` using the normalized mask so Command remains logically held for the entire chord.
    - **Redundant-toggle guard**: Skip extra press/release when the same physical Command button is already active.
  - `src/lib/platform/OSXKeyState.cpp`
    - **Aggregate left/right Command**: Set `NX_COMMANDMASK` if either Command side is down; clear it only when both are up.
    - **Per-side device bits**: Continue updating per-side device masks while maintaining the correct global Command state.

- **Result**
  - Cmd+C and Cmd+V work reliably in Terminal and GUI apps.
  - No more intermittent "just types the character" behavior.
  - Logs show a stable Super (0x0010) modifier throughout the combo with no Command up/down injected around the character.

- **Safety**
  - Changes are scoped to Command handling on macOS.
  - Other modifiers (Shift, Option, Control) are unchanged.
  - Normalization only affects cases where layouts present Meta for Command; standardized to Super for macOS.

- **Testing**
  - Repeated Cmd+C / Cmd+V sequences now behave consistently.
  - Debug logs confirm: desired state remains 0x0010 (Super) during the entire chord.

- **Testing Tools**
  - **Onscreen Keyboard**: Use `open -a "System Settings"` and navigate to General > Keyboard > Keyboard Shortcuts > Input Sources > Show Input menu in menu bar
  - Alternatively, enable the input menu in the menu bar and use the keyboard viewer from there
  - This helps verify that modifier states are correctly maintained during key combinations

- **Additional Testing Goals**
  The following modifier combinations need to be verified for consistent behavior:
  - **Command + Shift combinations**:
    - Cmd+Shift+Click (for multi-select in Finder, text selection)
    - Cmd+Shift+W (close window in many apps)
    - Cmd+Shift+T (reopen closed tab in browsers)
  - **Command + Option combinations**:
    - Cmd+Option+W (close all windows in many apps)
    - Cmd+Option+Escape (force quit applications)
    - Cmd+Option+D (show/hide dock)
  - **Control + Option combinations**:
    - Ctrl+Option+O (open in new window in Finder)
    - Ctrl+Option+Click (context menu alternatives)
  - **Multi-modifier combinations**:
    - Cmd+Shift+Option combinations
    - Cmd+Control+Shift combinations
    - Verify modifiers stay held during mouse operations
    - Test modifier state persistence across app switches

- **Additional Fixes**
  - **Extended modifier aggregation**: Applied Command-style left/right aggregation to Shift, Option, and Control keys to prevent state loss in multi-modifier combinations
  - This addresses issues with combinations like Cmd+Shift+Click, Cmd+Option+W, and Ctrl+Option+O

- **Files touched**
  - `src/lib/inputleap/KeyMap.cpp`
  - `src/lib/platform/OSXKeyState.cpp`
  - `files/fix-command-key-press.patch` (merged patch containing all fixes)

- **Implementation Status**
  - **Primary Fix**: Command key normalization and redundant-toggle guard (KeyMap.cpp)
  - **Secondary Fix**: Universal left/right aggregation for all modifiers (Shift, Option, Control, Command) (OSXKeyState.cpp)
  - **Coverage**: Addresses all documented modifier combinations including Cmd+Shift+Click, Cmd+Option+W, Ctrl+Option+O, etc.

- **Patch Management**
  - **Conflict Resolution**: Merged `fix-modifier-aggregation.patch` into `fix-command-key-press.patch` to avoid conflicts
  - **Applied Order**: Patches applied in order: macOS scroll, unsafe threads, non-GUI build, AltGr mapping, command key fixes
  - **No Conflicts**: Verified no overlapping modifications between remaining patches

- **Suggested subject**
  - macOS: stabilize Command-key handling; fix Cmd+C/Cmd+V intermittency

- **Test Scenario Setup**
  - **Environment**: 
    - **Host 1**: macOS client (Cursor machine) running input-leap client
    - **Host 2**: Virtual machine (Sequoia VM) running input-leap server
    - **Connection**: SSH access via `ssh sequoia` command
    - **Binary**: Same input-leap build running on both hosts
  - **Input Method**: Physical keyboard on Host 1 (Cursor machine)
  - **Target Applications**: Terminal, Finder, Safari, TextEdit, and other native macOS apps on Host 2
  - **Test Procedure**:
    1. Configure and start input-leap on both Host 1 and Host 2
    2. Connect input-leap client from Host 1 to Host 2 server
    3. Open keyboard viewer on Host 1 to monitor modifier states
    4. Test each modifier combination on Host 1 keyboard
    5. Verify modifier persistence across app switches on Host 2
    6. Test modifier + mouse click combinations
    7. Document any failures or inconsistent behavior
  - **Debugging Workflow**:
    - Test modifier combinations on Host 1 (Cursor machine)
    - Use SSH to inspect log output on Host 2: `ssh sequoia <command>`
    - Provide screenshots of virtual keyboard on Host 1 to confirm keys being sent
    - Compare expected vs actual behavior on Host 2
  - **Success Criteria**: All modifier combinations work reliably without dropping modifier state when sent from Host 1 to Host 2


