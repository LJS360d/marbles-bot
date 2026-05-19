const BottomTabCarousel = {
  mounted() {
    this.track = this.el.querySelector("[data-track]");
    this.prevBtn = this.el.querySelector("[data-action='prev']");
    this.nextBtn = this.el.querySelector("[data-action='next']");
    this.handleClick = (e) => {
      const action = e.currentTarget.dataset.action;
      const itemWidth = this.track.clientWidth / 5;
      const dir = action === "next" ? 1 : -1;
      this.track.scrollBy({ left: dir * itemWidth, behavior: "smooth" });
    };
    this.prevBtn.addEventListener("click", this.handleClick);
    this.nextBtn.addEventListener("click", this.handleClick);
    this.centerActive(true);
  },
  updated() {
    this.centerActive();
  },
  destroyed() {
    if (this.prevBtn) this.prevBtn.removeEventListener("click", this.handleClick);
    if (this.nextBtn) this.nextBtn.removeEventListener("click", this.handleClick);
  },
  centerActive(instant = false) {
    const scope = this.el.dataset.currentScope;
    if (!scope) return;
    const active = this.track.querySelector(`[data-scope="${scope}"]`);
    if (!active) return;
    const item = active.closest("li");
    if (!item) return;
    const target = item.offsetLeft - (this.track.clientWidth - item.clientWidth) / 2;
    this.track.scrollTo({ left: target, behavior: instant ? "auto" : "smooth" });
  },
};

export default BottomTabCarousel;
