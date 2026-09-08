{
  lib,
  platform,
  ...
}:

{
  # Remap Home/End to behave like Windows/Linux (line-wise movement) in Cocoa
  # text views. Apps need to be restarted after switching for this to apply.
  # Note: some apps (Electron, Firefox, terminal emulators) ignore this dict.
  home.file."Library/KeyBindings/DefaultKeyBinding.dict" = lib.mkIf platform.isDarwin {
    text = ''
      /* Remap Home / End keys to be correct */
      "\UF729" = "moveToBeginningOfLine:"; /* Home */
      "\UF72B" = "moveToEndOfLine:"; /* End */
      "$\UF729" = "moveToBeginningOfLineAndModifySelection:"; /* Shift + Home */
      "$\UF72B" = "moveToEndOfLineAndModifySelection:"; /* Shift + End */
      "^\UF729" = "moveToBeginningOfDocument:"; /* Ctrl + Home */
      "^\UF72B" = "moveToEndOfDocument:"; /* Ctrl + End */
      "$^\UF729" = "moveToBeginningOfDocumentAndModifySelection:"; /* Shift + Ctrl + Home */
      "$^\UF72B" = "moveToEndOfDocumentAndModifySelection:"; /* Shift + Ctrl + End */
    '';
  };
}
