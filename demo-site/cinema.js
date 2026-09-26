'use strict';
const film = document.getElementById('product-film');
const filmButton = document.getElementById('toggle-film');
const filmOverlay = document.getElementById('film-overlay');
const filmChapters = [...document.querySelectorAll('[data-time]')];
let pendingChapter = null;
function filmState() {
  const isPlaying = !film.paused && !film.ended;
  filmButton.textContent = isPlaying ? 'Ⅱ 暂停短片' : '▶ 播放短片';
  filmButton.setAttribute('aria-pressed', String(isPlaying));
  filmOverlay.hidden = isPlaying;
  filmOverlay.setAttribute('aria-label', film.currentTime > 0 && !film.ended ? '继续播放产品短片' : '播放产品短片');
}
async function playFilm() {
  try {
    if (film.ended) film.currentTime = 0;
    await film.play();
    document.getElementById('film-error').hidden = true;
  } catch {
    document.getElementById('film-error').hidden = false;
    filmState();
  }
}
filmButton.addEventListener('click', () => film.paused ? playFilm() : film.pause());
filmOverlay.addEventListener('click', playFilm);
['play', 'pause', 'ended'].forEach(event => film.addEventListener(event, filmState));
film.addEventListener('error', () => { document.getElementById('film-error').hidden = false; filmState(); });
film.addEventListener('loadedmetadata', () => {
  if (pendingChapter !== null) { film.currentTime = pendingChapter; pendingChapter = null; }
});
filmChapters.forEach(button => button.addEventListener('click', () => {
  const time = Number(button.dataset.time);
  if (film.readyState >= 1) film.currentTime = time;
  else pendingChapter = time;
  playFilm();
}));
film.addEventListener('timeupdate', () => {
  const time = film.currentTime;
  const seconds = Math.floor(time);
  document.getElementById('film-time').textContent = `00:${String(seconds).padStart(2,'0')} / 00:32`;
  const activeIndex = time < 6 ? 0 : time < 12 ? 1 : time < 18 ? 2 : time < 24 ? 3 : 4;
  filmChapters.forEach((button, i) => button.setAttribute('aria-pressed', String(i === activeIndex)));
});
// Pause when the viewer leaves the player; motion starts only on explicit play.
if ('IntersectionObserver' in window) {
  new IntersectionObserver(entries => { if (!entries[0].isIntersecting && !film.paused) film.pause(); }, {threshold:.1}).observe(film);
}
document.addEventListener('visibilitychange', () => { if(document.hidden) film.pause(); });
filmState();
