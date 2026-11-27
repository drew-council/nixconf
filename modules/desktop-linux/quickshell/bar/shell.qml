//@ pragma UseQApplication
//@ pragma RespectSystemStyle

import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    Variants {
        model: Quickshell.screens

        Bar {
            required property ShellScreen modelData
            screen: modelData
        }
    }

    // qs -c bar ipc call picker toggle <apps|clipboard|audio|monitors>
    IpcHandler {
        target: "picker"

        function toggle(kind: string): void {
            Pickers.toggle(kind, null);
        }

        function close(): void {
            Pickers.close();
        }
    }

    Toasts {}

    LazyLoader {
        active: Pickers.provider !== null && Pickers.anchor === null

        CenteredPicker {
            provider: Pickers.provider
        }
    }
}
