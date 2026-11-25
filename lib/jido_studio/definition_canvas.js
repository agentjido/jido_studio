(() => {
  if (customElements.get("jido-definition-canvas")) return;

  class DefinitionCanvas extends HTMLElement {
    connectedCallback() {
      this.viewport = this.querySelector("[data-canvas-viewport]");
      this.frame = this.querySelector("[data-canvas-frame]");
      this.scene = this.querySelector("[data-canvas-scene]");
      this.zoomLabel = this.querySelector("[data-canvas-zoom]");
      this.scale = 1;
      this.listeners = new AbortController();
      const options = { signal: this.listeners.signal };

      this.addEventListener("click", (event) => {
        const button = event.target.closest("[data-canvas-action]");
        if (button) this.zoom(button.dataset.canvasAction);
      }, options);

      this.viewport.addEventListener("keydown", (event) => this.onKey(event), options);
      this.viewport.addEventListener("pointerdown", (event) => this.beginPan(event), options);
      this.viewport.addEventListener("pointermove", (event) => this.pan(event), options);
      this.viewport.addEventListener("lostpointercapture", () => {
        this.drag = null;
        delete this.viewport.dataset.panning;
      }, options);

      this.resize = new ResizeObserver(() => this.render());
      this.resize.observe(this.scene);
      this.changes = new MutationObserver(() => this.render());
      this.changes.observe(this.scene, {
        subtree: true,
        childList: true,
        attributes: true,
        attributeFilter: ["aria-pressed", "data-highlight"],
      });

      this.setScale(Math.max(0.68, this.fitScale()), false);
    }

    disconnectedCallback() {
      this.listeners?.abort();
      this.resize?.disconnect();
      this.changes?.disconnect();
    }

    fitScale() {
      const width = this.viewport.clientWidth / this.scene.offsetWidth;
      const height = this.viewport.clientHeight / this.scene.offsetHeight;
      return Math.min(width, height, 1);
    }

    zoom(action) {
      switch (action) {
        case "in": this.setScale(this.scale * 1.25); break;
        case "out": this.setScale(this.scale / 1.25); break;
        case "fit": this.setScale(this.fitScale(), false); break;
      }
    }

    setScale(next, keepCenter = true) {
      const { clientWidth, clientHeight, scrollLeft, scrollTop } = this.viewport;
      const pivotX = clientWidth / 2;
      const pivotY = clientHeight / 2;
      const oldScale = this.scale;
      this.scale = Math.max(0.15, Math.min(2, next));
      this.render();

      this.viewport.scrollLeft = keepCenter ? (scrollLeft + pivotX) * this.scale / oldScale - pivotX : 0;
      this.viewport.scrollTop = keepCenter ? (scrollTop + pivotY) * this.scale / oldScale - pivotY : 0;
    }

    onKey(event) {
      if (event.target !== this.viewport || event.ctrlKey || event.metaKey || event.altKey) return;

      const direction = {
        ArrowLeft: [-72, 0], ArrowRight: [72, 0], ArrowUp: [0, -72], ArrowDown: [0, 72],
      }[event.key];

      if (direction) {
        event.preventDefault();
        this.viewport.scrollBy(...direction);
      } else {
        const action = { "+": "in", "=": "in", "-": "out", "0": "fit" }[event.key];
        if (action) {
          event.preventDefault();
          this.zoom(action);
        }
      }
    }

    beginPan(event) {
      if (event.pointerType !== "mouse" || event.button !== 0 || event.target.closest("button, a")) return;

      this.drag = {
        x: event.clientX,
        y: event.clientY,
        left: this.viewport.scrollLeft,
        top: this.viewport.scrollTop,
      };
      this.viewport.setPointerCapture(event.pointerId);
      this.viewport.dataset.panning = "true";
    }

    pan(event) {
      if (!this.drag) return;
      this.viewport.scrollLeft = this.drag.left + this.drag.x - event.clientX;
      this.viewport.scrollTop = this.drag.top + this.drag.y - event.clientY;
    }

    render() {
      const { offsetWidth, offsetHeight } = this.scene;
      this.frame.style.width = `${Math.ceil(offsetWidth * this.scale)}px`;
      this.frame.style.height = `${Math.ceil(offsetHeight * this.scale)}px`;
      this.scene.style.transform = `scale(${this.scale})`;
      const text = `${Math.round(this.scale * 100)}%`;
      if (this.zoomLabel.textContent !== text) this.zoomLabel.textContent = text;
      this.drawWires();
    }

    drawWires() {
      const origin = this.scene.getBoundingClientRect();
      const nodes = new Map();

      for (const node of this.scene.querySelectorAll("[data-canvas-node]")) {
        const bounds = node.getBoundingClientRect();
        nodes.set(node.dataset.canvasNode, {
          left: (bounds.left - origin.left) / this.scale,
          right: (bounds.right - origin.left) / this.scale,
          top: (bounds.top - origin.top) / this.scale,
          bottom: (bounds.bottom - origin.top) / this.scale,
          middle: (bounds.top - origin.top + bounds.height / 2) / this.scale,
        });
      }

      let returnLane = 0;
      for (const wire of this.scene.querySelectorAll("[data-from][data-to]")) {
        const from = nodes.get(wire.dataset.from);
        const to = nodes.get(wire.dataset.to);
        if (!from || !to) continue;

        if (from.right <= to.left) {
          const label = wire.parentElement.querySelector("[data-wire-label]");
          this.drawForward(wire, label, from, to, nodes.values());
        } else {
          const stagger = returnLane % 5;
          const begin = from.right - 24 - stagger * 12;
          const end = to.left + 24 + stagger * 12;
          const rail = Math.max(from.bottom, to.bottom) + 26 + stagger * 22;
          wire.setAttribute("d", `M ${begin} ${from.bottom} V ${rail} H ${end} V ${to.bottom}`);
          returnLane += 1;
        }
      }
    }

    drawForward(wire, label, from, to, nodes) {
      const centerX = (from.right + to.left) / 2;
      const centerY = (from.middle + to.middle) / 2;
      const obstacles = [...nodes].filter((node) =>
        node.left > from.right && node.right < to.left &&
        node.top <= Math.max(from.middle, to.middle) &&
        node.bottom >= Math.min(from.middle, to.middle),
      );

      let labelY = centerY;
      if (obstacles.length > 0) {
        const rail = Math.min(...obstacles.map((node) => node.top)) - 16;
        const begin = from.right + 14;
        const end = to.left - 14;
        wire.setAttribute("d", `M ${from.right} ${from.middle} H ${begin} V ${rail} H ${end} V ${to.middle} H ${to.left}`);
        labelY = rail;
      } else {
        wire.setAttribute("d", `M ${from.right} ${from.middle} C ${centerX} ${from.middle}, ${centerX} ${to.middle}, ${to.left} ${to.middle}`);
      }

      if (label) {
        label.setAttribute("x", centerX);
        label.setAttribute("y", labelY - 8);
      }
    }
  }

  customElements.define("jido-definition-canvas", DefinitionCanvas);
})();
