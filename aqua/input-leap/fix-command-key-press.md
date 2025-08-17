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
  - No more intermittent “just types the character” behavior.
  - Logs show a stable Super (0x0010) modifier throughout the combo with no Command up/down injected around the character.

- **Safety**
  - Changes are scoped to Command handling on macOS.
  - Other modifiers (Shift, Option, Control) are unchanged.
  - Normalization only affects cases where layouts present Meta for Command; standardized to Super for macOS.

- **Testing**
  - Repeated Cmd+C / Cmd+V sequences now behave consistently.
  - Debug logs confirm: desired state remains 0x0010 (Super) during the entire chord.

- **Files touched**
  - `src/lib/inputleap/KeyMap.cpp`
  - `src/lib/platform/OSXKeyState.cpp`

- **Suggested subject**
  - macOS: stabilize Command-key handling; fix Cmd+C/Cmd+V intermittency


