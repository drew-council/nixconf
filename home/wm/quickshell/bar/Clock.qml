import QtQuick
import Quickshell

BarButton {
    id: root

    property bool showDate: false
    readonly property date now: clock.date

    function calendar(date) {
        const year = date.getFullYear();
        const month = date.getMonth();
        const today = date.getDate();
        const firstWeekday = new Date(year, month, 1).getDay();
        const days = new Date(year, month + 1, 0).getDate();

        let cells = Array(firstWeekday).fill("  ");
        for (let day = 1; day <= days; day++) {
            const cell = String(day).padStart(2, " ");
            cells.push(day === today ? `<b><font color="${Theme.accent}">${cell}</font></b>` : cell);
        }

        let rows = ["Su Mo Tu We Th Fr Sa"];
        for (let i = 0; i < cells.length; i += 7)
            rows.push(cells.slice(i, i + 7).join(" "));

        const title = Qt.formatDate(date, "yyyy MMMM");
        return `<big>${title}</big><pre>${rows.join("\n")}</pre>`;
    }

    text: {
        if (showDate)
            return Qt.formatDate(now, "yyyy-MM-dd");
        const hours = String(now.getHours() % 12 || 12).padStart(2, "0");
        return `${hours}:${Qt.formatTime(now, "mm")}`;
    }
    font.pixelSize: 14
    font.bold: true
    tooltip: calendar(now)
    tooltipFormat: Text.RichText

    onClicked: showDate = !showDate

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }
}
