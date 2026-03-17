export const onSwipeImpl = (onLeft) => (onRight) => () => {
  let startX = 0;
  let startY = 0;
  let startTime = 0;
  document.addEventListener('touchstart', (e) => {
    startX = e.touches[0].clientX;
    startY = e.touches[0].clientY;
    startTime = Date.now();
  }, { passive: true });
  document.addEventListener('touchend', (e) => {
    const dx = e.changedTouches[0].clientX - startX;
    const dy = e.changedTouches[0].clientY - startY;
    const dt = Date.now() - startTime;
    // Swipe: >40px horizontal, more horizontal than vertical, under 500ms
    if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy) && dt < 500) {
      if (dx < 0) onLeft();
      else onRight();
    }
  }, { passive: true });
};
