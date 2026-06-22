/* =========================================================
   Mesh Player — script.js
   Vanilla JS. No dependencies. Respects prefers-reduced-motion.
   ========================================================= */

(() => {
  "use strict";

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ---------------------------------------------------------
     Nav: scrolled state + mobile menu toggle
     --------------------------------------------------------- */
  const nav = document.getElementById("nav");
  const burger = document.getElementById("navBurger");
  const mobileMenu = document.getElementById("navMobile");

  const onScroll = () => {
    nav.classList.toggle("is-scrolled", window.scrollY > 12);
  };
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  if (burger && mobileMenu) {
    burger.addEventListener("click", () => {
      const open = mobileMenu.classList.toggle("is-open");
      burger.setAttribute("aria-expanded", String(open));
      burger.setAttribute("aria-label", open ? "Close menu" : "Open menu");
    });

    mobileMenu.querySelectorAll("a").forEach((link) => {
      link.addEventListener("click", () => {
        mobileMenu.classList.remove("is-open");
        burger.setAttribute("aria-expanded", "false");
        burger.setAttribute("aria-label", "Open menu");
      });
    });
  }

  /* ---------------------------------------------------------
     Scroll reveal for feature cards / deep-dive visuals
     --------------------------------------------------------- */
  const revealTargets = document.querySelectorAll(
    "[data-reveal], .theater__visual, .library__visual"
  );

  if (reduceMotion) {
    revealTargets.forEach((el) => el.classList.add("is-visible"));
  } else if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            // small stagger for cards sharing a row
            const delay = entry.target.dataset.reveal ? Math.random() * 90 : 0;
            setTimeout(() => entry.target.classList.add("is-visible"), delay);
            io.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.18, rootMargin: "0px 0px -40px 0px" }
    );
    revealTargets.forEach((el) => io.observe(el));
  } else {
    revealTargets.forEach((el) => el.classList.add("is-visible"));
  }

  /* ---------------------------------------------------------
     Hero transport: play/pause toggle (purely demonstrative)
     --------------------------------------------------------- */
  const playToggle = document.getElementById("playToggle");
  const playIcon = document.getElementById("playIcon");
  const scrubFill = document.getElementById("scrubFill");

  const ICON_PLAY = '<path d="M6 4l14 8-14 8z" fill="currentColor"/>';
  const ICON_PAUSE = '<path d="M6 4h4v16H6zM14 4h4v16h-4z" fill="currentColor"/>';

  let isPlaying = true;
  let scrubTimer = null;
  let scrubPct = 42;

  function startScrub() {
    if (scrubTimer || reduceMotion) return;
    scrubTimer = setInterval(() => {
      scrubPct = scrubPct >= 100 ? 0 : scrubPct + 0.4;
      if (scrubFill) scrubFill.style.width = `${scrubPct}%`;
    }, 250);
  }
  function stopScrub() {
    clearInterval(scrubTimer);
    scrubTimer = null;
  }

  if (playToggle && playIcon) {
    playToggle.addEventListener("click", () => {
      isPlaying = !isPlaying;
      playIcon.innerHTML = isPlaying ? ICON_PAUSE : ICON_PLAY;
      playToggle.setAttribute("aria-label", isPlaying ? "Pause" : "Play");
      isPlaying ? startScrub() : stopScrub();
    });
    // initial state: "playing" demo, so show pause icon
    playIcon.innerHTML = ICON_PAUSE;
    playToggle.setAttribute("aria-label", "Pause");
    startScrub();
  }

  /* ---------------------------------------------------------
     Hero lyric cycler — simple ring buffer, mimics synced lyrics
     --------------------------------------------------------- */
  const lyricSets = [
    [
      "Loading the last track",
      "Pulling the waveform in",
      "Every format, every mix, decoded right",
      "Nothing lost between the studio and you",
      "Just press play",
    ],
    [
      "No re-encoding, no waiting",
      "Your library, exactly as you ripped it",
      "Lossless in, lossless out",
      "Spatial mixes routed automatically",
      "This is the part you'll forget is even running",
    ],
    [
      "Folders become collections",
      "Genres sort themselves while you listen",
      "One tap, and it's a favorite forever",
      "Theater Mode is one key away",
      "Sit back. It's already playing.",
    ],
  ];

  const lyricsContainer = document.getElementById("heroLyrics");
  let lyricSetIndex = 0;
  let lyricLineIndex = 2; // start mid-set so "current" is visually centered

  function renderLyrics() {
    if (!lyricsContainer) return;
    const lines = lyricSets[lyricSetIndex];
    lyricsContainer.innerHTML = "";

    // show: 1 past (hidden on mobile via CSS), current, 1 next
    const order = [
      { idx: lyricLineIndex - 1, state: "past" },
      { idx: lyricLineIndex, state: "current" },
      { idx: lyricLineIndex + 1, state: "next" },
    ];

    order.forEach(({ idx, state }) => {
      const text = lines[(idx + lines.length) % lines.length];
      const p = document.createElement("p");
      p.className = "lyric-line";
      p.dataset.state = state;
      p.textContent = text;
      lyricsContainer.appendChild(p);
    });
  }

  function advanceLyrics() {
    lyricLineIndex += 1;
    const lines = lyricSets[lyricSetIndex];
    if (lyricLineIndex >= lines.length) {
      lyricLineIndex = 0;
      lyricSetIndex = (lyricSetIndex + 1) % lyricSets.length;
    }
    renderLyrics();
  }

  renderLyrics();
  if (!reduceMotion) {
    setInterval(advanceLyrics, 3600);
  }

  /* ---------------------------------------------------------
     Automated Screenshot Slideshow Logic
     --------------------------------------------------------- */
  const slideshow = document.getElementById("screenshotSlideshow");
  const dotsContainer = document.getElementById("slideshowDots");

  if (slideshow && dotsContainer) {
    const slides = slideshow.querySelectorAll(".slide");
    const dots = dotsContainer.querySelectorAll(".s-dot");
    let currentSlideIndex = 0;
    let slideshowInterval = null;

    const changeSlide = (nextIndex) => {
      slides[currentSlideIndex].classList.remove("active");
      dots[currentSlideIndex].classList.remove("active");

      currentSlideIndex = nextIndex;

      slides[currentSlideIndex].classList.add("active");
      dots[currentSlideIndex].classList.add("active");
    };

    const startSlideshow = () => {
      if (reduceMotion) return;
      slideshowInterval = setInterval(() => {
        const nextIndex = (currentSlideIndex + 1) % slides.length;
        changeSlide(nextIndex);
      }, 4500); // Transitions automatically every 4.5 seconds
    };

    // Manual navigation control via indicators
    dots.forEach((dot) => {
      dot.addEventListener("click", () => {
        clearInterval(slideshowInterval);
        const targetIndex = parseInt(dot.getAttribute("data-index"), 10);
        if (targetIndex !== currentSlideIndex) {
          changeSlide(targetIndex);
        }
        startSlideshow();
      });
    });

    startSlideshow();
  }
})();
