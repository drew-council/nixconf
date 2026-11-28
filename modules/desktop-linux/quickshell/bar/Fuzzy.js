.pragma library

// match scores text as an in-order, case-insensitive subsequence of query.
// It returns null when text does not contain every query character.
// Consecutive matches and matches at word starts score higher.
function match(query, text) {
    const q = query.toLowerCase().replace(/\s+/g, "");
    const t = text.toLowerCase();
    const positions = [];
    let score = 0;
    let j = -1;
    for (const c of q) {
        const found = t.indexOf(c, j + 1);
        if (found < 0)
            return null;
        if (found === j + 1)
            score += 4;
        if (found === 0 || /[\s\-_.\/]/.test(t[found - 1]))
            score += 3;
        score += 1 - Math.min(found - j - 1, 10) * 0.1;
        positions.push(found);
        j = found;
    }
    // Prefer shorter labels among equal matches.
    return { score: score - t.length * 0.01, positions };
}

// filter ranks items by how well query matches their label,
// falling back to their search text with a penalty.
// An item's weight, such as a launch count, breaks near ties,
// and orders the items when query is empty.
// Results otherwise keep the original order.
function filter(items, query) {
    if (query.trim() === "")
        return items.map(item => ({ item, positions: [] }))
            .sort((a, b) => (b.item.weight ?? 0) - (a.item.weight ?? 0));
    const results = [];
    items.forEach((item, index) => {
        let m = match(query, item.label);
        if (!m && item.search) {
            m = match(query, item.search);
            if (m)
                m = { score: m.score - 5, positions: [] };
        }
        if (m) {
            const score = m.score + Math.log2(1 + (item.weight ?? 0)) * 0.4;
            results.push({ item, positions: m.positions, score, index });
        }
    });
    return results.sort((a, b) => b.score - a.score || a.index - b.index);
}

function escape(s) {
    return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// highlight returns StyledText with the matched positions bold in color
// and the rest dimmed.
function highlight(text, positions, color, dim) {
    if (positions.length === 0)
        return escape(text);
    const hit = new Set(positions);
    let out = "";
    for (let i = 0; i < text.length; i++) {
        const c = escape(text[i]);
        out += hit.has(i) ? `<b><font color="${color}">${c}</font></b>` : c;
    }
    return `<font color="${dim}">${out}</font>`;
}
