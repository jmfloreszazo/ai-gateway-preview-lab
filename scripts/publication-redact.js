(() => {
    const marker = 'data-ai-gateway-publication-mask';

    function restore() {
        document.querySelectorAll(`[${marker}]`).forEach(element => element.remove());
        document.querySelectorAll('x-pw-glass').forEach(element => element.remove());
    }

    function cover(privateNames) {
        restore();
        const escaped = privateNames.filter(Boolean).map(value =>
            value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
        const pattern = new RegExp([
            ...escaped,
            '[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}',
            '[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}'
        ].join('|'), 'gi');
        const rectangles = [];

        function addRectangle(rectangle, element) {
            let left = Math.max(0, rectangle.left);
            let top = Math.max(0, rectangle.top);
            let right = Math.min(innerWidth, rectangle.right);
            let bottom = Math.min(innerHeight, rectangle.bottom);

            for (let ancestor = element; ancestor && ancestor !== document.body; ancestor = ancestor.parentElement) {
                const style = getComputedStyle(ancestor);
                const bounds = ancestor.getBoundingClientRect();
                const cell = ancestor.getAttribute('role') === 'gridcell';
                if (cell || /hidden|clip|auto|scroll/.test(style.overflowX)) {
                    left = Math.max(left, bounds.left);
                    right = Math.min(right, bounds.right);
                }
                if (cell || /hidden|clip|auto|scroll/.test(style.overflowY)) {
                    top = Math.max(top, bounds.top);
                    bottom = Math.min(bottom, bounds.bottom);
                }
            }

            if (right <= left || bottom <= top) return;
            rectangles.push({
                x: Math.max(0, Math.floor(left) - 1),
                y: Math.max(0, Math.floor(top) - 1),
                width: Math.ceil(right - left) + 2,
                height: Math.ceil(bottom - top) + 2
            });
        }

        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        while (walker.nextNode()) {
            const node = walker.currentNode;
            const parent = node.parentElement;
            if (!parent || ['SCRIPT', 'STYLE', 'NOSCRIPT'].includes(parent.tagName)) continue;
            pattern.lastIndex = 0;
            let match;
            while ((match = pattern.exec(node.textContent)) !== null) {
                const range = document.createRange();
                range.setStart(node, match.index);
                range.setEnd(node, match.index + match[0].length);
                for (const rectangle of range.getClientRects()) addRectangle(rectangle, parent);
            }
        }

        document.querySelectorAll('input, textarea').forEach(element => {
            const secretField = /password|api.?key|token|secret/i.test(
                `${element.type} ${element.name} ${element.getAttribute('aria-label') || ''}`);
            pattern.lastIndex = 0;
            if (secretField || pattern.test(element.value)) {
                addRectangle(element.getBoundingClientRect(), element);
            }
        });

        document.querySelectorAll('button').forEach(element => {
            const label = element.getAttribute('aria-label') || '';
            if (/^Account menu/i.test(label) ||
                /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i.test(element.textContent || '')) {
                addRectangle(element.getBoundingClientRect(), element);
            }
        });

        for (const rectangle of rectangles) {
            const overlay = document.createElement('div');
            overlay.setAttribute(marker, 'true');
            overlay.setAttribute('aria-hidden', 'true');
            Object.assign(overlay.style, {
                position: 'fixed',
                left: `${rectangle.x}px`,
                top: `${rectangle.y}px`,
                width: `${rectangle.width}px`,
                height: `${rectangle.height}px`,
                background: '#222222',
                zIndex: '2147483647',
                pointerEvents: 'none'
            });
            document.body.appendChild(overlay);
        }

        return { width: innerWidth, height: innerHeight, rectangles };
    }

    globalThis.aiGatewayPublication = { cover, restore };
})();