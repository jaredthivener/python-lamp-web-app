// /static/script.js
// Enhanced LampApp
// - Cached DOM lookups
// - Abortable fetches
// - rAF-driven physics & recoil
// - DocumentFragment for activity rendering
// - Defensive checks around anime.js
// - Robust cleanup

class LampApp {
  constructor(options = {}) {
    // Configurable physics & timings
    this.cfg = Object.assign({
      pullThreshold: 50,
      maxPull: 150,
      maxSway: 80,
      springForce: 0.12,
      damping: 0.88,
      dashboardUrl: '/api/v1/lamp/dashboard',
      toggleUrl: '/api/v1/lamp/toggle',
      syncIntervalMs: 5000,
      maxParticles: 25,
      particleLifetimeMs: 3000
    }, options);

    // Cached DOM references (defensive)
    this.dom = {
      lamp: document.getElementById('lamp'),
      stringHandle: document.getElementById('stringHandle'),
      stringPath: document.getElementById('stringPath'),
      stringHighlight: document.getElementById('stringHighlight'),
      stringSvg: document.querySelector('.string-svg'),
      particlesContainer: document.getElementById('particles'),
      todayToggles: document.getElementById('todayToggles'),
      currentState: document.getElementById('currentState'),
      lifetimeToggles: document.getElementById('lifetimeToggles'),
      uniqueSessions: document.getElementById('uniqueSessions'),
      activityList: document.getElementById('activityList'),
      html: document.documentElement
    };

    // Basic guard: abort init if essential DOM missing
    if (!this.dom.lamp || !this.dom.stringHandle || !this.dom.stringPath || !this.dom.stringSvg) {
      console.warn('LampApp: essential DOM elements missing. Aborting initialization.');
      return;
    }

    // State
    this.isOn = this.dom.lamp.classList.contains('on');
    this.isAnimating = false;
    this.isDragging = false;
    this.isRecoiling = false;
    this.particles = [];
    this.eventCleanup = [];
    this.updateIntervalId = null;
    this.syncController = null; // AbortController for dashboard fetches

    // Drag/physics
    this.dragStart = { x: 0, y: 0 };
    this.current = { pull: 0, sway: 0 };
    this.velocity = { x: 0, y: 0 };

    // String points (5 points)
    this.stringPoints = Array.from({ length: 5 }, (_, i) => ({ x: 60, y: i * 20, vx: 0, vy: 0 }));

    // Initialize
    this._rafIds = new Set();
    this.init();
  }

  /* ----------------------
     Initialization
  ---------------------- */
  init() {
    console.info('LampApp: init');
    this.bindEvents();
    this.createInitialParticles();
    this.updateStringCurve(); // sets initial d path for stringPath/highlight
    this.updateHandlePosition(); // sets initial handle transform/position
    this.startPeriodicSync();
    this.loadDashboard().catch(() => {}); // load dashboard once
    this.animateEntranceSafely();
  }

  /* ----------------------
     Event binding / cleanup
  ---------------------- */
  bindEvents() {
    const { lamp } = this.dom;

    // lamp click & keyboard (Enter/Space)
    const onLampClick = (e) => {
      // ignore clicks on pull-string container (so dragging doesn't toggle by accident)
      if (e.target.closest && e.target.closest('.pull-string-container')) return;
      this.toggleLampState('user');
    };
    const onLampKey = (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        this.toggleLampState('keyboard');
      }
    };

    lamp.addEventListener('click', onLampClick);
    lamp.addEventListener('keydown', onLampKey);
    this.eventCleanup.push(() => lamp.removeEventListener('click', onLampClick));
    this.eventCleanup.push(() => lamp.removeEventListener('keydown', onLampKey));

    // global key 'l' toggles lamp
    const onGlobalKey = (e) => {
      if (e.key && e.key.toLowerCase() === 'l') this.toggleLampState('shortcut');
    };
    document.addEventListener('keydown', onGlobalKey);
    this.eventCleanup.push(() => document.removeEventListener('keydown', onGlobalKey));

    // beforeunload: save minimal state (non-blocking)
    const onBeforeUnload = () => {
      try { localStorage.setItem('lampState', JSON.stringify({ isOn: this.isOn })); } catch (err) {}
    };
    window.addEventListener('beforeunload', onBeforeUnload);
    this.eventCleanup.push(() => window.removeEventListener('beforeunload', onBeforeUnload));

    // Drag events for string (mouse & touch)
    this._bindDragHandlers();
  }

  _bindDragHandlers() {
    const elements = [this.dom.stringSvg, this.dom.stringHandle].filter(Boolean);
    const start = (e) => this._startDrag(e);
    const move = (e) => this._onDrag(e);
    const end = (e) => this._endDrag(e);

    elements.forEach(el => {
      el.addEventListener('mousedown', start);
      el.addEventListener('touchstart', start, { passive: false });
      el.addEventListener('contextmenu', (ev) => ev.preventDefault());
      this.eventCleanup.push(() => el.removeEventListener('mousedown', start));
      this.eventCleanup.push(() => el.removeEventListener('touchstart', start));
    });

    // global move/end
    document.addEventListener('mousemove', move);
    document.addEventListener('mouseup', end);
    document.addEventListener('touchmove', move, { passive: false });
    document.addEventListener('touchend', end);
    this.eventCleanup.push(() => document.removeEventListener('mousemove', move));
    this.eventCleanup.push(() => document.removeEventListener('mouseup', end));
    this.eventCleanup.push(() => document.removeEventListener('touchmove', move));
    this.eventCleanup.push(() => document.removeEventListener('touchend', end));
  }

  /* ----------------------
     Drag handlers & physics
  ---------------------- */
  _startDrag(e) {
    // prevent text selection/scroll while dragging
    if (e.cancelable) e.preventDefault();

    this.isDragging = true;
    this.isRecoiling = false;
    this.velocity = { x: 0, y: 0 };

    const t = e.touches && e.touches[0] ? e.touches[0] : e;
    this.dragStart = { x: t.clientX, y: t.clientY };

    // UI feedback
    this.dom.stringSvg.style.cursor = 'grabbing';
    this.dom.stringHandle.classList && this.dom.stringHandle.classList.add('dragging');
    document.body.style.userSelect = 'none';
    document.body.style.cursor = 'grabbing';
  }

  _onDrag(e) {
    if (!this.isDragging) return;
    if (e.cancelable) e.preventDefault();

    const t = e.touches && e.touches[0] ? e.touches[0] : e;
    const delta = { x: t.clientX - this.dragStart.x, y: t.clientY - this.dragStart.y };

    // update current pull/sway clamped to config
    this.current.pull = Math.max(0, Math.min(delta.y, this.cfg.maxPull));
    this.current.sway = Math.max(-this.cfg.maxSway, Math.min(delta.x * 0.8, this.cfg.maxSway));
    this.velocity = { x: delta.x * 0.08, y: delta.y * 0.08 };

    this.updateStringCurve();
    this.updateHandlePosition();

    // small rotation for visual feedback
    const lastPoint = this.stringPoints[this.stringPoints.length - 1];
    const intensity = Math.min(1, this.current.pull / this.cfg.maxPull);
    this.dom.stringHandle.setAttribute('transform', `rotate(${this.current.sway * 0.08} ${lastPoint.x} ${lastPoint.y}) scale(${1 + intensity * 0.12})`);
  }

  _endDrag() {
    if (!this.isDragging) return;
    this.isDragging = false;

    // reset UI
    this.dom.stringSvg.style.cursor = 'grab';
    this.dom.stringHandle.classList && this.dom.stringHandle.classList.remove('dragging');
    document.body.style.userSelect = '';
    document.body.style.cursor = '';

    // trigger or recoil based on threshold
    if (this.current.pull >= this.cfg.pullThreshold) {
      this._triggerPullAnimation();
    } else {
      this._startSpaghettiRecoil();
    }
  }

  /* ----------------------
     String drawing helpers
  ---------------------- */
  updateStringCurve() {
    // recompute stringPoints influenced by current.pull and current.sway
    for (let i = 0; i < 5; i++) {
      const p = this.stringPoints[i];
      p.x = 60;      // reset base x
      p.y = i * 20;  // reset base y
    }

    const forceStrength = this.current.pull / this.cfg.maxPull;

    // Build path with quadratic segments — keep structure predictable
    let pathData = `M 60 0`;
    for (let i = 1; i < 5; i++) {
      const influence = Math.pow(i / 4, 1.5);
      const point = this.stringPoints[i];
      point.y += this.current.pull * influence * 0.4;
      const swayOffset = this.current.sway * influence * 0.6;
      point.x += swayOffset + Math.sin(i * 0.8) * swayOffset * 0.3;
      if (i > 1) point.y += forceStrength * 15 * Math.sin(i * 0.5);

      // Append quadratic to next anchor (keep consistent pattern)
      const next = this.stringPoints[Math.min(i + 1, 4)];
      pathData += ` Q ${Math.round(point.x)} ${Math.round(point.y)} ${Math.round(next.x)} ${Math.round(next.y)}`;
    }

    // Apply to both main path and highlight if available
    this.dom.stringPath.setAttribute('d', pathData);
    if (this.dom.stringHighlight) this.dom.stringHighlight.setAttribute('d', pathData);
  }

  updateHandlePosition() {
    // Keep handle at last point
    const last = this.stringPoints[4];
    if (!last) return;

    // If stringHandle is an SVG element with cx/cy attributes
    try {
      if ('setAttribute' in this.dom.stringHandle) {
        this.dom.stringHandle.setAttribute('cx', String(last.x));
        this.dom.stringHandle.setAttribute('cy', String(last.y));
        // ensure transform reflects current sway/pull
        const scale = 1 + (this.current.pull / this.cfg.maxPull) * 0.1;
        this.dom.stringHandle.setAttribute('transform', `rotate(${this.current.sway * 0.08} ${last.x} ${last.y}) scale(${scale})`);
      }
    } catch (err) {
      // ignore if not SVG
      // console.debug('updateHandlePosition: handle not svg-like', err);
    }
  }

  /* ----------------------
     Recoil animation (rAF)
  ---------------------- */
  _startSpaghettiRecoil() {
    this.isRecoiling = true;
    if (this._recoilLoopId) cancelAnimationFrame(this._recoilLoopId);
    const loop = () => {
      if (!this.isRecoiling) return;
      // simple spring physics towards base positions
      let energy = 0;
      for (let i = 1; i < 5; i++) {
        const pt = this.stringPoints[i];
        const targetX = 60;
        const targetY = i * 20;
        const fx = (targetX - pt.x) * this.cfg.springForce;
        const fy = (targetY - pt.y) * this.cfg.springForce;

        pt.vx = (pt.vx + fx) * this.cfg.damping;
        pt.vy = (pt.vy + fy) * this.cfg.damping;
        pt.x += pt.vx;
        pt.y += pt.vy;
        energy += Math.abs(pt.vx) + Math.abs(pt.vy);
      }

      // apply to current pull/sway (natural damping)
      this.velocity.y = (this.velocity.y - this.current.pull * this.cfg.springForce * 0.5) * this.cfg.damping;
      this.velocity.x = (this.velocity.x - this.current.sway * this.cfg.springForce * 0.5) * this.cfg.damping;
      this.current.pull = Math.max(-30, Math.min(this.cfg.maxPull, this.current.pull + this.velocity.y));
      this.current.sway = Math.max(-this.cfg.maxSway, Math.min(this.cfg.maxSway, this.current.sway + this.velocity.x));

      this.updateStringCurve();
      this.updateHandlePosition();

      if (energy > 0.5 || Math.abs(this.current.pull) > 0.5 || Math.abs(this.current.sway) > 0.5) {
        this._recoilLoopId = requestAnimationFrame(loop);
        this._rafIds.add(this._recoilLoopId);
      } else {
        this._rafIds.delete(this._recoilLoopId);
        this.finishSpaghettiRecoil();
      }
    };
    this._recoilLoopId = requestAnimationFrame(loop);
    this._rafIds.add(this._recoilLoopId);
  }

  finishSpaghettiRecoil() {
    this.isRecoiling = false;
    this.velocity = { x: 0, y: 0 };
    // If anime.js present, do a nice elastic settle; otherwise linear settle
    if (typeof anime !== 'undefined') {
      anime({
        targets: { p: this.current.pull, s: this.current.sway },
        p: 0, s: 0,
        duration: 700,
        easing: 'easeOutElastic(1, 0.8)',
        update: (anim) => {
          this.current.pull = anim.animations[0].currentValue;
          this.current.sway = anim.animations[1].currentValue;
          this.updateStringCurve();
          this.updateHandlePosition();
        },
        complete: () => this.resetStringPosition()
      });
    } else {
      // fallback: quick linear reset
      this.current.pull = 0; this.current.sway = 0;
      this.updateStringCurve();
      this.updateHandlePosition();
      this.resetStringPosition();
    }
  }

  /* ----------------------
     Pull-trigger animation & toggle
  ---------------------- */
  _triggerPullAnimation() {
    // stop any ongoing recoil
    this.isRecoiling = false;
    if (typeof anime !== 'undefined') {
      anime({
        targets: { p: this.current.pull, s: this.current.sway },
        p: this.current.pull + 25, s: this.current.sway * 1.3,
        duration: 120,
        easing: 'easeOutQuad',
        update: (anim) => {
          this.current.pull = anim.animations[0].currentValue;
          this.current.sway = anim.animations[1].currentValue;
          this.updateStringCurve();
          this.updateHandlePosition();
        },
        complete: () => {
          // secondary wobble
          anime({
            targets: { p: this.current.pull, s: this.current.sway },
            p: [this.current.pull + 25, -20, 15, -8, 3, 0],
            s: [this.current.sway * 1.3, this.current.sway * -0.4, this.current.sway * 0.2, this.current.sway * -0.1, 0],
            duration: 1000,
            easing: 'easeOutElastic(1, 0.6)',
            update: (anim) => {
              this.current.pull = anim.animations[0].currentValue;
              this.current.sway = anim.animations[1].currentValue;
              this.updateStringCurve();
              this.updateHandlePosition();
            },
            complete: () => this.resetStringPosition()
          });
        }
      });
    } else {
      // no anime - quick fallback and reset
      setTimeout(() => this.resetStringPosition(), 800);
    }

    // Slight debounce to prevent double toggles
    if (this.isAnimating) return;
    this.isAnimating = true;
    setTimeout(() => { this.isAnimating = false; }, 800);

    // Toggle lamp (user-initiated)
    this.toggleLampState('pull');
  }

  resetStringPosition() {
    const originalPath = 'M 60 0 Q 60 20 60 40 Q 60 60 60 80';
    try {
      this.dom.stringPath.setAttribute('d', originalPath);
      if (this.dom.stringHighlight) this.dom.stringHighlight.setAttribute('d', originalPath);
      this.dom.stringHandle.setAttribute('cx', '60');
      this.dom.stringHandle.setAttribute('cy', '80');
      this.dom.stringHandle.removeAttribute('transform');
    } catch (err) {
      // ignore if DOM shape different
    }

    // reset internal points
    this.stringPoints = Array.from({ length: 5 }, (_, i) => ({ x: 60, y: i * 20, vx: 0, vy: 0 }));
    this.current.pull = 0; this.current.sway = 0;
    this.velocity = { x: 0, y: 0 };
  }

  /* ----------------------
     Lamp state toggle + backend sync
  ---------------------- */
  async toggleLampState(source = 'user') {
    if (this.isAnimating) return;
    console.debug('toggleLampState:', source);
    this.isAnimating = true;

    // local optimistic toggle
    this.isOn = !this.isOn;
    this.updateLampVisuals();

    // Call API (non-blocking). Use abort controller to avoid old requests interfering.
    try {
      const controller = new AbortController();
      const sig = controller.signal;
      // short timeout fallback: if no response in 3s, abort (improves responsiveness)
      const timeoutId = setTimeout(() => controller.abort(), 3000);

      const res = await fetch(this.cfg.toggleUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ toggle: true, source }),
        signal: sig
      }).finally(() => clearTimeout(timeoutId));

      if (res && res.ok) {
        const data = await res.json().catch(() => null) || {};
        if (typeof data.is_on === 'boolean' && data.is_on !== this.isOn) {
          this.isOn = data.is_on;
          this.updateLampVisuals();
        }
        // slight delay before dashboard refresh to let backend write
        setTimeout(() => this.loadDashboard().catch(() => {}), 120);
      }
    } catch (err) {
      // network error or abort -> keep optimistic UI, but inform console
      console.warn('toggleLampState: toggle API failed or timed out', err);
    } finally {
      // clear animation lock after short delay to allow visual animations to complete
      setTimeout(() => { this.isAnimating = false; }, 700);
    }
  }

  updateLampVisuals() {
    // toggle classes
    this.dom.lamp.classList.toggle('on', this.isOn);
    this.dom.lamp.classList.toggle('off', !this.isOn);
    // update document title and theme
    document.title = `Lamp App - ${this.isOn ? 'ON' : 'OFF'}`;
    this.dom.html.setAttribute('data-theme', this.isOn ? 'light' : 'dark');

    // animate lamp swing & glow if anime available
    if (typeof anime !== 'undefined') {
      // small swing
      anime({
        targets: this.dom.lamp,
        rotate: [
          { value: -3, duration: 200, easing: 'easeOutQuad' },
          { value: 2, duration: 200, easing: 'easeInOutQuad' },
          { value: -1, duration: 200, easing: 'easeInOutQuad' },
          { value: 0, duration: 300, easing: 'easeOutElastic(1, 0.3)' }
        ]
      });

      // bulb & glow effects
      if (this.isOn) {
        anime({ targets: '.light-glow', scale: [0.8, 1.08, 1], duration: 600, easing: 'easeOutElastic(1, 0.4)' });
        anime({ targets: '.bulb-glass', scale: [1, 1.06, 1], duration: 500, easing: 'easeOutElastic(1, 0.3)' });
        anime({ targets: '.shade-body', scale: [1, 1.02, 1], duration: 400, easing: 'easeOutQuad' });
      } else {
        anime({ targets: '.light-glow', scale: 1, duration: 300, easing: 'easeOutQuad' });
        anime({ targets: '.bulb-glass', scale: [1, 0.98, 1], duration: 300, easing: 'easeOutQuad' });
        anime({ targets: '.shade-body', scale: 1, duration: 300, easing: 'easeOutQuad' });
      }
    } else {
      // fallback: ensure CSS classes reflect state (already done above)
    }

    // trigger particle burst when turning on
    if (this.isOn) this.triggerLightParticles();
  }

  /* ----------------------
     Particles (ambient & light)
  ---------------------- */
  createInitialParticles() {
    const count = window.innerWidth < 768 ? Math.floor(this.cfg.maxParticles * 0.6) : this.cfg.maxParticles;
    for (let i = 0; i < count; i++) this._createAmbientParticle();
  }

  _createAmbientParticle() {
    if (!this.dom.particlesContainer) return;
    const el = document.createElement('div');
    el.className = 'particle';
    const size = Math.random() * 4 + 2;
    const x = Math.random() * window.innerWidth;
    const y = Math.random() * window.innerHeight;
    const delay = Math.random() * 3;
    el.style.left = `${x}px`;
    el.style.top = `${y}px`;
    el.style.width = `${size}px`;
    el.style.height = `${size}px`;
    el.style.animationDelay = `${delay}s`;
    this.dom.particlesContainer.appendChild(el);
    this.particles.push(el);

    // schedule removal
    setTimeout(() => {
      if (el.parentNode) el.remove();
      const idx = this.particles.indexOf(el);
      if (idx > -1) this.particles.splice(idx, 1);
    }, this.cfg.particleLifetimeMs + delay * 1000);
  }

  triggerLightParticles() {
    // warm light rays from lamp center
    const lampRect = this.dom.lamp.getBoundingClientRect();
    const lampCenterX = lampRect.left + lampRect.width / 2;
    const lampCenterY = lampRect.top + 80;

    const makeRay = (i) => {
      const el = document.createElement('div');
      el.style.position = 'fixed';
      el.style.left = `${lampCenterX}px`;
      el.style.top = `${lampCenterY}px`;
      el.style.width = '8px';
      el.style.height = '8px';
      el.style.background = 'radial-gradient(circle,#fff8dc,#ffd700)';
      el.style.borderRadius = '50%';
      el.style.pointerEvents = 'none';
      el.style.zIndex = 100;
      el.style.boxShadow = '0 0 10px #ffd700';
      document.body.appendChild(el);

      const angle = (i / 12) * Math.PI * 2;
      const distance = 100 + Math.random() * 50;
      const endX = Math.cos(angle) * distance;
      const endY = Math.sin(angle) * distance + 30;

      if (typeof anime !== 'undefined') {
        anime({
          targets: el,
          translateX: endX,
          translateY: endY,
          scale: [0, 1.5, 0],
          opacity: [0, 1, 0],
          duration: 1200,
          easing: 'easeOutQuad',
          complete: () => el.remove()
        });
      } else {
        // fallback: simple fade + translate using CSS transitions
        el.style.transition = 'transform 1200ms ease-out, opacity 1200ms ease-out';
        requestAnimationFrame(() => {
          el.style.transform = `translate(${endX}px, ${endY}px) scale(1.2)`;
          el.style.opacity = '0';
          setTimeout(() => el.remove(), 1200);
        });
      }
    };

    // create rays
    for (let i = 0; i < 12; i++) setTimeout(() => makeRay(i), i * 80);

    // ambient glows
    for (let i = 0; i < 6; i++) {
      setTimeout(() => {
        const glow = document.createElement('div');
        glow.style.position = 'fixed';
        glow.style.left = `${lampCenterX}px`;
        glow.style.top = `${lampCenterY + 40}px`;
        glow.style.width = '20px';
        glow.style.height = '20px';
        glow.style.background = 'radial-gradient(circle, rgba(255,248,220,0.6), transparent)';
        glow.style.borderRadius = '50%';
        glow.style.pointerEvents = 'none';
        glow.style.zIndex = 99;
        glow.style.filter = 'blur(8px)';
        document.body.appendChild(glow);

        const randomX = (Math.random() - 0.5) * 200;
        const randomY = Math.random() * 100 + 50;
        if (typeof anime !== 'undefined') {
          anime({
            targets: glow,
            translateX: randomX,
            translateY: randomY,
            scale: [0, 2, 0],
            opacity: [0, 0.8, 0],
            duration: 2000,
            easing: 'easeOutCubic',
            complete: () => glow.remove()
          });
        } else {
          glow.style.transition = 'transform 2000ms ease-out, opacity 2000ms ease-out';
          requestAnimationFrame(() => {
            glow.style.transform = `translate(${randomX}px, ${randomY}px) scale(2)`;
            glow.style.opacity = '0';
            setTimeout(() => glow.remove(), 2000);
          });
        }
      }, i * 150);
    }
  }

  /* ----------------------
     Dashboard: fetch & render
     - Abort previous fetch when new one starts
     - Defensive parsing & rendering (won't crash on malformed data)
  ---------------------- */
  async loadDashboard() {
    // Abort previous
    if (this.syncController) {
      try { this.syncController.abort(); } catch (e) {}
      this.syncController = null;
    }
    this.syncController = new AbortController();
    const signal = this.syncController.signal;

    // Update title while loading for feedback
    const prevTitle = document.title;
    document.title = 'Loading... - Lamp App';

    try {
      const res = await fetch(this.cfg.dashboardUrl, { signal, cache: 'no-store' });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      this._safeUpdateDashboard(data);
    } catch (err) {
      if (err.name === 'AbortError') {
        console.debug('loadDashboard: aborted previous request');
      } else {
        console.warn('loadDashboard failed:', err);
        // fallback to safe defaults
        this._safeUpdateDashboard({
          current_state: { is_on: this.isOn },
          today_stats: { total_toggles: 0, unique_sessions: 0 },
          total_lifetime_toggles: 0,
          recent_activities: []
        });
      }
    } finally {
      document.title = prevTitle;
      this.syncController = null;
    }
  }

  _safeUpdateDashboard(data = {}) {
    // defensive data extraction
    try {
      const isOn = !!(data.current_state && data.current_state.is_on);
      this.isOn = isOn;
      this.updateLampVisuals();

      // update small stats if present
      if (this.dom.todayToggles) {
        this.dom.todayToggles.textContent = String((data.today_stats && typeof data.today_stats.total_toggles === 'number') ? data.today_stats.total_toggles : '0');
      }
      if (this.dom.lifetimeToggles) {
        const lifetime = typeof data.total_lifetime_toggles === 'number' ? data.total_lifetime_toggles : 0;
        this.dom.lifetimeToggles.textContent = lifetime.toLocaleString();
      }
      if (this.dom.uniqueSessions) {
        this.dom.uniqueSessions.textContent = String((data.today_stats && typeof data.today_stats.unique_sessions === 'number') ? data.today_stats.unique_sessions : '0');
      }
      if (this.dom.currentState) {
        // nice short indicator
        this.dom.currentState.textContent = this.isOn ? '🔥 ON' : '🌙 OFF';
        this.dom.currentState.style.color = this.isOn ? '#f1c40f' : '#95a5a6';
      }

      // recent activities
      this._renderRecentActivities(data.recent_activities || []);
    } catch (err) {
      console.error('dashboard render failed (defensive):', err);
    }
  }

  _renderRecentActivities(activities = []) {
    const container = this.dom.activityList;
    if (!container) return;

    // Clear quickly
    container.innerHTML = '';

    if (!Array.isArray(activities) || activities.length === 0) {
      const noAct = document.createElement('div');
      noAct.className = 'loading-state';
      noAct.textContent = 'No recent activity';
      container.appendChild(noAct);
      return;
    }

    const frag = document.createDocumentFragment();
    const max = Math.min(50, activities.length);
    for (let i = 0; i < max; i++) {
      const a = activities[i];
      const item = document.createElement('div');
      item.className = 'activity-item';

      const left = document.createElement('div');
      left.className = 'activity-action';

      const icon = document.createElement('div');
      const isOn = (a.action === 'on' || a.action === 'toggle_on' || a.action === true);
      icon.className = `activity-icon ${isOn ? 'on' : 'off'}`;
      icon.setAttribute('aria-hidden', 'true');

      const text = document.createElement('span');
      text.className = 'activity-text';
      text.textContent = isOn ? 'Turned ON' : 'Turned OFF';

      left.appendChild(icon);
      left.appendChild(text);

      const time = document.createElement('span');
      time.className = 'activity-time';
      // safe timestamp formatting
      try {
        const d = new Date(a.timestamp || a.ts || a.time || Date.now());
        time.textContent = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
      } catch (err) {
        time.textContent = '-';
      }

      item.appendChild(left);
      item.appendChild(time);
      frag.appendChild(item);
    }

    container.appendChild(frag);
  }

  /* ----------------------
     Periodic sync (debounced / guarded)
  ---------------------- */
  startPeriodicSync() {
    // Clear previous if exists
    if (this.updateIntervalId) clearInterval(this.updateIntervalId);

    // Run once immediately
    this.loadDashboard().catch(() => {});

    // Then periodic
    this.updateIntervalId = setInterval(() => {
      // avoid syncing while user animating or dragging
      if (this.isAnimating || this.isDragging) return;
      this.loadDashboard().catch(() => {});
      // replenish ambient particles if low
      if (this.particles.length < (this.cfg.maxParticles * 0.6)) this._createAmbientParticle();
    }, this.cfg.syncIntervalMs);
  }

  /* ----------------------
     Entrance animations (safe)
  ---------------------- */
  animateEntranceSafely() {
    if (typeof anime === 'undefined') {
      // fallback: small CSS-based reveal (no-op here)
      return;
    }

    anime.timeline()
      .add({
        targets: '.app-header',
        translateY: [-50, 0],
        opacity: [0, 1],
        duration: 700,
        easing: 'easeOutExpo'
      })
      .add({
        targets: '.lamp-container',
        scale: [0.6, 1],
        opacity: [0, 1],
        duration: 900,
        easing: 'easeOutElastic(1, 0.5)',
        offset: 150
      })
      .add({
        targets: '.stats-container',
        translateY: [30, 0],
        opacity: [0, 1],
        duration: 700,
        easing: 'easeOutExpo',
        offset: 450
      });
  }

  /* ----------------------
     Utility: aggressive cleanup
  ---------------------- */
  destroy() {
    // clear intervals
    if (this.updateIntervalId) {
      clearInterval(this.updateIntervalId);
      this.updateIntervalId = null;
    }
    // abort pending fetch
    if (this.syncController) {
      try { this.syncController.abort(); } catch (e) {}
      this.syncController = null;
    }
    // cancel rAFs
    this._rafIds.forEach(id => cancelAnimationFrame(id));
    this._rafIds.clear();

    // remove events
    this.eventCleanup.forEach(fn => {
      try { fn(); } catch (e) {}
    });
    this.eventCleanup = [];

    // remove particles
    this.particles.forEach(p => { try { if (p.parentNode) p.remove(); } catch (e) {} });
    this.particles = [];

    // remove some inline styles we set
    try {
      this.dom.stringSvg.style.cursor = '';
      document.body.style.userSelect = '';
      document.body.style.cursor = '';
    } catch (e) {}

    console.info('LampApp: destroyed & cleaned up');
  }
}

/* ----------------------
   Bootstrap on DOMContentLoaded
---------------------- */
document.addEventListener('DOMContentLoaded', () => {
  if (!window.lampApp) {
    window.lampApp = new LampApp();

    // expose helpers for debugging
    window.lampAppDebug = {
      reloadDashboard: () => window.lampApp.loadDashboard().catch(() => {}),
      destroy: () => window.lampApp.destroy(),
      toggle: (src) => window.lampApp.toggleLampState(src || 'debug')
    };
  }
});
