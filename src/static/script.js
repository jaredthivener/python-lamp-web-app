// Lamp Interactive App - Enhanced Hanging Lamp Version
class LampApp {
    /**
     * Generate a cryptographically secure random string of the given length.
     * @param {number} length
     * @returns {string}
     */
    static generateSecureRandomString(length) {
        const array = new Uint8Array(length);
        window.crypto.getRandomValues(array);
        // Convert to base64url (URL-safe, no padding)
        return btoa(String.fromCharCode.apply(null, array))
            .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '').substr(0, length);
    }

    constructor() {
        console.log('Initializing LampApp...');
        this.lamp = document.getElementById('lamp');
        if (!this.lamp) {
            console.error('Lamp element not found in the DOM.');
        }
        this.stringHandle = document.getElementById('stringHandle');
        this.stringPath = document.getElementById('stringPath');
        this.stringHighlight = document.getElementById('stringHighlight');
        this.stringSvg = document.querySelector('.string-svg');
        this.html = document.documentElement;
        this.particlesContainer = document.getElementById('particles');

        this.isOn = false;
        this.particles = [];
        this.isAnimating = false;
        this.sessionId = null;

        // --- Verlet String Physics ---
        // SVG viewBox is 120×120. String is anchored at (60, 0).
        this.NUM_NODES = 6;
        this.SEGMENT_LENGTH = 16; // natural rest length of each segment (SVG units)
        this.GRAVITY = 0.4;
        this.DAMPING = 0.97;        // velocity damping per frame (air resistance)
        this.CONSTRAINT_ITERS = 8;  // distance-constraint solver iterations per frame

        this._initStringNodes();

        // Drag state
        this.isDragging = false;
        this.dragSvgX = 60;
        this.dragSvgY = (this.NUM_NODES - 1) * this.SEGMENT_LENGTH;

        // Pull-to-toggle state
        this.pullThreshold = 45;    // SVG units below rest to trigger toggle
        this.toggleTriggered = false;

        // rAF handle
        this._rafId = null;

        this.init();
    }

    // -----------------------------------------------------------------------
    // Verlet String Physics Helpers
    // -----------------------------------------------------------------------

    /**
     * Initialise Verlet nodes. Each node: { x, y, px, py, pinned }
     * px/py encode the previous position, giving Verlet velocity implicitly.
     */
    _initStringNodes() {
        this.nodes = [];
        for (let i = 0; i < this.NUM_NODES; i++) {
            const y = i * this.SEGMENT_LENGTH;
            this.nodes.push({ x: 60, y, px: 60, py: y, pinned: i === 0 });
        }
    }

    /**
     * One Verlet integration + constraint-solver pass.
     * When dragging, the last node is pinned to (dragSvgX, dragSvgY).
     */
    _stepPhysics() {
        const n = this.nodes;

        // 1 — Integrate: infer velocity from (current - previous), apply gravity
        for (let i = 0; i < n.length; i++) {
            if (n[i].pinned) continue;
            const vx = (n[i].x - n[i].px) * this.DAMPING;
            const vy = (n[i].y - n[i].py) * this.DAMPING;
            n[i].px = n[i].x;
            n[i].py = n[i].y;
            n[i].x += vx;
            n[i].y += vy + this.GRAVITY;
        }

        // 2 — Hard-pin the last node to the drag target while dragging
        if (this.isDragging) {
            const last = n[n.length - 1];
            last.px = last.x;
            last.py = last.y;
            last.x = this.dragSvgX;
            last.y = this.dragSvgY;
        }

        // 3 — Enforce segment-length constraints (multiple iterations = stability)
        for (let iter = 0; iter < this.CONSTRAINT_ITERS; iter++) {
            // Always re-anchor node 0 first
            n[0].x = 60; n[0].y = 0;

            for (let i = 0; i < n.length - 1; i++) {
                const a = n[i];
                const b = n[i + 1];
                const dx = b.x - a.x;
                const dy = b.y - a.y;
                const dist = Math.sqrt(dx * dx + dy * dy) || 0.001;
                const diff = (dist - this.SEGMENT_LENGTH) / dist;
                const corr = diff * 0.5;

                if (!a.pinned)                                           { a.x += dx * corr; a.y += dy * corr; }
                if (!b.pinned && !(this.isDragging && i + 1 === n.length - 1)) { b.x -= dx * corr; b.y -= dy * corr; }
            }

            // Re-anchor node 0 after constraint pass
            n[0].x = 60; n[0].y = 0;
        }
    }

    /**
     * Convert a mouse/touch client coordinate into SVG user-space coordinates.
     * Uses the SVG element's own CTM so viewBox scaling, preserveAspectRatio
     * letterboxing, and any CSS transforms are all handled automatically.
     */
    _clientToSvg(clientX, clientY) {
        const pt = this.stringSvg.createSVGPoint();
        pt.x = clientX;
        pt.y = clientY;
        return pt.matrixTransform(this.stringSvg.getScreenCTM().inverse());
    }

    /**
     * Render node positions as a smooth quadratic Bézier spline.
     * Uses midpoint Bézier technique: each original node becomes a control point,
     * ensuring the path passes smoothly through every midpoint.
     */
    _renderString() {
        const n = this.nodes;
        if (n.length < 2) return;

        let d = `M ${n[0].x.toFixed(2)} ${n[0].y.toFixed(2)}`;

        for (let i = 0; i < n.length - 1; i++) {
            const cx = n[i].x.toFixed(2);
            const cy = n[i].y.toFixed(2);
            if (i < n.length - 2) {
                // Middle segments: endpoint is the midpoint → smooth through all interior nodes
                const mx = ((n[i].x + n[i + 1].x) / 2).toFixed(2);
                const my = ((n[i].y + n[i + 1].y) / 2).toFixed(2);
                d += ` Q ${cx} ${cy} ${mx} ${my}`;
            } else {
                // Last segment: endpoint IS the last node — no L kink, handle stays on curve
                d += ` Q ${cx} ${cy} ${n[i + 1].x.toFixed(2)} ${n[i + 1].y.toFixed(2)}`;
            }
        }

        const last = n[n.length - 1];

        this.stringPath.setAttribute('d', d);
        this.stringHighlight.setAttribute('d', d);

        // Position the handle ellipse at the last node (cx/cy only — no scale tricks)
        this.stringHandle.setAttribute('cx', last.x.toFixed(2));
        this.stringHandle.setAttribute('cy', last.y.toFixed(2));

        // Rotate the handle to follow the local string direction
        const prev = n[n.length - 2];
        const angle = Math.atan2(last.y - prev.y, last.x - prev.x) * (180 / Math.PI) - 90;
        this.stringHandle.setAttribute('transform',
            `rotate(${angle.toFixed(1)} ${last.x.toFixed(2)} ${last.y.toFixed(2)})`
        );
    }

    /**
     * Main rAF loop — integrates physics, renders, checks pull threshold.
     */
    _animationLoop() {
        this._stepPhysics();
        this._renderString();

        // Check pull-to-toggle threshold during active drag
        if (this.isDragging && !this.toggleTriggered) {
            const restY = (this.NUM_NODES - 1) * this.SEGMENT_LENGTH;
            if (this.dragSvgY - restY >= this.pullThreshold) {
                this.toggleTriggered = true;
                this._onPullTriggered();
            }
        }

        this._rafId = requestAnimationFrame(() => this._animationLoop());
    }

    /**
     * Fired when the user has pulled past the threshold.
     * Releases the drag pin and imparts an upward slingshot velocity.
     */
    _onPullTriggered() {
        // Impart a sharp upward velocity via Verlet's previous-position trick
        const last = this.nodes[this.nodes.length - 1];
        const snap = 18; // SVG units of upward snap per frame
        last.py = last.y + snap; // py > y ⟹ net upward velocity next integration
        last.px = last.x;

        // Release the drag pin
        this.isDragging = false;
        this.stringSvg.style.cursor = 'grab';
        this.stringHandle.classList.remove('dragging');
        document.body.style.userSelect = '';
        document.body.style.cursor = '';

        // Toggle after a short delay so the snap feels causal
        setTimeout(() => this.toggleLamp(), 120);
    }

    // -----------------------------------------------------------------------
    // Initialisation
    // -----------------------------------------------------------------------

    init() {
        console.log('Initializing events and syncing with backend...');
        this.bindEvents();
        this.createParticles();

        // Start the Verlet physics + render loop
        this._animationLoop();

        // Sync with backend state on load
        this.syncWithBackend();

        // Load dashboard data
        this.loadDashboard();

        // Periodic sync and dashboard updates
        setInterval(() => {
            this.syncWithBackend();
            this.loadDashboard();
        }, 5000);

        // Add entrance animation
        this.animateEntrance();
        console.log('Initialization complete.');
    }

    bindEvents() {
        // Lamp click/keyboard events (clicking anywhere on the lamp except string)
        if (this.lamp) {
            this.lamp.addEventListener('click', (e) => {
                // Don't trigger if clicking on string elements
                if (!e.target.closest('.pull-string-container')) {
                    e.preventDefault();
                    this.toggleLamp();
                }
            });

            this.lamp.addEventListener('keydown', (e) => {
                if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    this.toggleLamp();
                }
            });
        }

        // String drag events
        this.bindStringDragEvents();

        // Keyboard shortcuts
        document.addEventListener('keydown', (e) => {
            if (e.key === 'l' || e.key === 'L') {
                this.toggleLamp();
            }
        });

        // Prevent context menu on string
        this.stringHandle.addEventListener('contextmenu', (e) => e.preventDefault());

        // Window events
        window.addEventListener('beforeunload', () => {
            localStorage.setItem('lampState', JSON.stringify({
                isOn: this.isOn
            }));
        });

        // Load saved state
        this.loadState();
    }

    bindStringDragEvents() {
        const startDrag = (e) => this.startDrag(e);
        [this.stringSvg, this.stringHandle].forEach(el => {
            el.addEventListener('mousedown', startDrag);
            el.addEventListener('touchstart', startDrag, { passive: false });
            el.addEventListener('contextmenu', (e) => e.preventDefault());
        });

        document.addEventListener('mousemove', (e) => this.onDrag(e));
        document.addEventListener('mouseup',   (e) => this.endDrag(e));
        document.addEventListener('touchmove', (e) => this.onDrag(e), { passive: false });
        document.addEventListener('touchend',  (e) => this.endDrag(e));
    }

    startDrag(e) {
        e.preventDefault();
        this.isDragging = true;
        this.toggleTriggered = false;

        const clientX = e.touches ? e.touches[0].clientX : e.clientX;
        const clientY = e.touches ? e.touches[0].clientY : e.clientY;
        const pos = this._clientToSvg(clientX, clientY);
        this.dragSvgX = pos.x;
        this.dragSvgY = pos.y;

        this.stringSvg.style.cursor = 'grabbing';
        this.stringHandle.classList.add('dragging');
        document.body.style.userSelect = 'none';
        document.body.style.cursor = 'grabbing';
    }

    onDrag(e) {
        if (!this.isDragging) return;
        e.preventDefault();

        const clientX = e.touches ? e.touches[0].clientX : e.clientX;
        const clientY = e.touches ? e.touches[0].clientY : e.clientY;
        const pos = this._clientToSvg(clientX, clientY);

        // Constrain X so the string stays mostly centred
        this.dragSvgX = Math.max(10, Math.min(110, pos.x));
        // Allow free downward pull; block pulling above the anchor
        this.dragSvgY = Math.max(5, pos.y);
    }

    endDrag(e) {
        if (!this.isDragging) return;
        this.isDragging = false;

        // If released past threshold but _onPullTriggered hasn't fired yet, trigger now
        if (!this.toggleTriggered) {
            const restY = (this.NUM_NODES - 1) * this.SEGMENT_LENGTH;
            const last  = this.nodes[this.nodes.length - 1];
            if (last.y - restY >= this.pullThreshold) {
                this.toggleTriggered = true;
                this._onPullTriggered();
                return; // _onPullTriggered already cleans up cursors
            }
        }

        // Natural release — Verlet physics handles the recoil automatically
        this.stringSvg.style.cursor = 'grab';
        this.stringHandle.classList.remove('dragging');
        document.body.style.userSelect = '';
        document.body.style.cursor = '';
    }

    updateLampFromAPI(data) {
        // Update lamp state from API response
        this.isOn = data.is_on;

        // Update lamp classes to trigger CSS animations
        this.lamp.classList.toggle('on', this.isOn);
        this.lamp.classList.toggle('off', !this.isOn);

        // Add a small delay to let CSS animations start, then enhance with JS animations
        setTimeout(() => {
            this.animateLampSwing();
        }, 50);

        // Update theme
        this.updateTheme();

        // Trigger particle effects
        if (this.isOn) {
            this.triggerLightParticles();
        }

        // Update page title
        document.title = `Lamp App - ${data.status.toUpperCase()}`;
    }

    toggleLampLocal() {
        // Fallback method for local-only toggle
        this.isOn = !this.isOn;

        // Update lamp classes to trigger CSS animations
        this.lamp.classList.toggle('on', this.isOn);
        this.lamp.classList.toggle('off', !this.isOn);

        // Add a small delay to let CSS animations start, then enhance with JS animations
        setTimeout(() => {
            this.animateLampSwing();
        }, 50);

        // Update theme
        this.updateTheme();

        // Trigger particle effects
        if (this.isOn) {
            this.triggerLightParticles();
        }
    }

    animateLampSwing() {
        // Create a gentle swinging motion
        anime({
            targets: this.lamp,
            rotate: [
                { value: -3, duration: 200, easing: 'easeOutQuad' },
                { value: 2, duration: 200, easing: 'easeInOutQuad' },
                { value: -1, duration: 200, easing: 'easeInOutQuad' },
                { value: 0, duration: 300, easing: 'easeOutElastic(1, 0.3)' }
            ]
        });

        // Always reset .light-glow before animating
        const lightGlow = document.querySelector('.light-glow');
        if (lightGlow) {
            lightGlow.style.opacity = this.isOn ? '1' : '0';
            lightGlow.style.transform = 'scale(0.8)';
        }

        // Enhance the CSS animations with JavaScript
        if (this.isOn) {
            // Animate the glow scale and ensure opacity
            anime({
                targets: '.light-glow',
                scale: [0.8, 1.1, 1],
                opacity: [0.7, 1],
                duration: 600,
                easing: 'easeOutElastic(1, 0.4)',
                update: anim => {
                    if (lightGlow) {
                        lightGlow.style.opacity = '1';
                    }
                }
            });

            // Animate the bulb glass with a subtle pulse
            anime({
                targets: '.bulb-glass',
                scale: [1, 1.08, 1],
                duration: 500,
                easing: 'easeOutElastic(1, 0.3)'
            });

            // Add a warm pulse to the shade body
            anime({
                targets: '.shade-body',
                scale: [1, 1.02, 1],
                duration: 400,
                easing: 'easeOutQuad'
            });
        } else {
            // When turning off, fade out the glow and animate bulb
            if (lightGlow) {
                anime({
                    targets: lightGlow,
                    scale: [1, 0.8],
                    opacity: [1, 0],
                    duration: 350,
                    easing: 'easeOutQuad',
                    complete: () => {
                        lightGlow.style.opacity = '0';
                        lightGlow.style.transform = 'scale(0.8)';
                    }
                });
            }
            anime({
                targets: '.bulb-glass',
                scale: [1, 0.98, 1],
                duration: 300,
                easing: 'easeOutQuad'
            });
        }
    }

    createClickFeedback() {
        // Visual feedback when sound is not available
        const feedback = document.createElement('div');
        feedback.style.cssText = `
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            width: 60px;
            height: 60px;
            border: 3px solid var(--accent);
            border-radius: 50%;
            pointer-events: none;
            z-index: 1000;
        `;

        document.body.appendChild(feedback);

        anime({
            targets: feedback,
            scale: [0, 1.5],
            opacity: [1, 0],
            duration: 600,
            easing: 'easeOutQuad',
            complete: () => feedback.remove()
        });
    }

    updateTheme() {
        const newTheme = this.isOn ? 'light' : 'dark';
        this.html.setAttribute('data-theme', newTheme);

        // Animate background transition
        anime({
            targets: '.background-gradient',
            opacity: [1, 0.8, 1],
            duration: 400,
            easing: 'easeInOutQuad'
        });
    }

    createParticles() {
        const particleCount = window.innerWidth < 768 ? 15 : 25;

        for (let i = 0; i < particleCount; i++) {
            this.createParticle();
        }
    }

    createParticle() {
        const particle = document.createElement('div');
        particle.className = 'particle';

        const size = Math.random() * 4 + 2;
        const x = Math.random() * window.innerWidth;
        const y = Math.random() * window.innerHeight;
        const delay = Math.random() * 3;

        particle.style.cssText = `
            left: ${x}px;
            top: ${y}px;
            width: ${size}px;
            height: ${size}px;
            animation-delay: ${delay}s;
        `;

        this.particlesContainer.appendChild(particle);
        this.particles.push(particle);

        // Remove particle after animation
        setTimeout(() => {
            if (particle.parentNode) {
                particle.remove();
                const index = this.particles.indexOf(particle);
                if (index > -1) this.particles.splice(index, 1);
            }
        }, 3000 + delay * 1000);
    }

    triggerLightParticles() {
        // Create light rays emanating from inside the lamp shade
        const lampRect = this.lamp.getBoundingClientRect();
        const lampCenterX = lampRect.left + lampRect.width / 2;
        const lampCenterY = lampRect.top + 80; // Position inside the shade

        // Create warm light particles
        for (let i = 0; i < 12; i++) {
            setTimeout(() => {
                const particle = document.createElement('div');
                particle.style.cssText = `
                    position: fixed;
                    left: ${lampCenterX}px;
                    top: ${lampCenterY}px;
                    width: 8px;
                    height: 8px;
                    background: radial-gradient(circle, #fff8dc, #ffd700);
                    border-radius: 50%;
                    pointer-events: none;
                    z-index: 100;
                    box-shadow: 0 0 10px #ffd700;
                `;

                document.body.appendChild(particle);

                const angle = (i / 12) * Math.PI * 2;
                const distance = 100 + Math.random() * 50;
                const endX = Math.cos(angle) * distance;
                const endY = Math.sin(angle) * distance + 30; // Bias downward for lamp light

                anime({
                    targets: particle,
                    translateX: endX,
                    translateY: endY,
                    scale: [0, 1.5, 0],
                    opacity: [0, 1, 0],
                    duration: 1200,
                    easing: 'easeOutQuad',
                    complete: () => particle.remove()
                });
            }, i * 80);
        }

        // Create additional ambient glow particles
        for (let i = 0; i < 6; i++) {
            setTimeout(() => {
                const glowParticle = document.createElement('div');
                glowParticle.style.cssText = `
                    position: fixed;
                    left: ${lampCenterX}px;
                    top: ${lampCenterY + 40}px;
                    width: 20px;
                    height: 20px;
                    background: radial-gradient(circle, rgba(255, 248, 220, 0.6), transparent);
                    border-radius: 50%;
                    pointer-events: none;
                    z-index: 99;
                    filter: blur(8px);
                `;

                document.body.appendChild(glowParticle);

                const randomX = (Math.random() - 0.5) * 200;
                const randomY = Math.random() * 100 + 50;

                anime({
                    targets: glowParticle,
                    translateX: randomX,
                    translateY: randomY,
                    scale: [0, 2, 0],
                    opacity: [0, 0.8, 0],
                    duration: 2000,
                    easing: 'easeOutCubic',
                    complete: () => glowParticle.remove()
                });
            }, i * 150);
        }
    }

    animateEntrance() {
        // Stagger animations for entrance
        anime.timeline()
            .add({
                targets: '.app-header',
                translateY: [-50, 0],
                opacity: [0, 1],
                duration: 800,
                easing: 'easeOutExpo'
            })
            .add({
                targets: '.lamp-container',
                scale: [0.5, 1],
                opacity: [0, 1],
                duration: 1000,
                easing: 'easeOutElastic(1, 0.5)',
                offset: 200
            })
            .add({
                targets: '.controls, .status-indicator',
                translateY: [30, 0],
                opacity: [0, 1],
                duration: 600,
                easing: 'easeOutQuad',
                offset: 600
            })
            .add({
                targets: '.stats-container',
                translateY: [30, 0],
                opacity: [0, 1],
                duration: 800,
                easing: 'easeOutExpo',
                offset: 800
            });
    }

    loadState() {
        try {
            const saved = localStorage.getItem('lampState');
            if (saved) {
                // Parse the saved state but don't restore it since we always start in dark mode
                // const state = JSON.parse(saved);

                // Optionally restore lamp state (commented out to always start in dark mode)
                // if (state.isOn) {
                //     this.toggleLamp();
                // }
            }
        } catch (error) {
            console.log('Could not load saved state:', error);
        }
    }

    async syncWithBackend() {
        // Add visual indicator
        document.title = 'Loading... - Lamp App';

        try {
            const response = await fetch('/api/v1/lamp/status');
            if (response.ok) {
                const data = await response.json();
                // Set initial state from backend and trigger animations
                this.isOn = data.is_on;
                this.lamp.classList.toggle('on', this.isOn);
                this.lamp.classList.toggle('off', !this.isOn);
                this.updateTheme();

                // Update page title to show sync status
                document.title = `Lamp App - ${data.status.toUpperCase()}`;
            } else {
                document.title = 'Lamp App - API Error';
            }
        } catch (error) {
            document.title = 'Lamp App - No Connection';
        }
    }

    // Dashboard methods
    async loadDashboard() {
        console.log('Loading dashboard data...');
        try {
            const response = await fetch('/api/v1/lamp/dashboard');
            if (response.ok) {
                const data = await response.json();
                console.log('Dashboard data received:', data);
                this.updateDashboard(data);
            } else {
                console.error('Dashboard API error:', response.status);
                // Set default values if API fails
                this.updateDashboard({
                    current_state: { is_on: false },
                    today_stats: { total_toggles: 0, unique_sessions: 0 },
                    total_lifetime_toggles: 0,
                    recent_activities: []
                });
            }
        } catch (error) {
            console.warn('Dashboard update failed:', error);
            // Set default values if API fails
            this.updateDashboard({
                current_state: { is_on: false },
                today_stats: { total_toggles: 0, unique_sessions: 0 },
                total_lifetime_toggles: 0,
                recent_activities: []
            });
        }
    }

    updateDashboard(data) {
        console.log('Updating dashboard with data:', data);

        // Update current state
        const currentStateEl = document.getElementById('currentState');
        if (currentStateEl) {
            currentStateEl.textContent = data.current_state.is_on ? '🔥 ON' : '🌙 OFF';
            currentStateEl.style.color = data.current_state.is_on ? '#f1c40f' : '#95a5a6';
        } else {
            console.error('currentState element not found');
        }

        // Update today's toggles
        const todayTogglesEl = document.getElementById('todayToggles');
        if (todayTogglesEl) {
            todayTogglesEl.textContent = data.today_stats ? data.today_stats.total_toggles : '0';
        } else {
            console.error('todayToggles element not found');
        }

        // Update lifetime toggles
        const lifetimeTogglesEl = document.getElementById('lifetimeToggles');
        if (lifetimeTogglesEl) {
            lifetimeTogglesEl.textContent = data.total_lifetime_toggles.toLocaleString();
        } else {
            console.error('lifetimeToggles element not found');
        }

        // Update unique sessions
        const uniqueSessionsEl = document.getElementById('uniqueSessions');
        if (uniqueSessionsEl) {
            uniqueSessionsEl.textContent = data.today_stats ? data.today_stats.unique_sessions : '0';
        } else {
            console.error('uniqueSessions element not found');
        }

        // Update recent activities
        this.updateRecentActivities(data.recent_activities);
    }

    updateRecentActivities(activities) {
        const activityListEl = document.getElementById('activityList');
        if (!activityListEl) return;

        if (!activities || activities.length === 0) {
            activityListEl.innerHTML = '<div class="loading-state">No recent activity</div>';
            return;
        }

        const activitiesHtml = activities.map(activity => {
            const date = new Date(activity.timestamp);
            const timeStr = date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
            const iconClass = activity.action === 'on' ? 'on' : 'off';
            const actionText = activity.action === 'on' ? 'Turned ON' : 'Turned OFF';

            return `
                <div class="activity-item">
                    <div class="activity-action">
                        <div class="activity-icon ${iconClass}"></div>
                        <span class="activity-text">${actionText}</span>
                    </div>
                    <span class="activity-time">${timeStr}</span>
                </div>
            `;
        }).join('');

        activityListEl.innerHTML = activitiesHtml;
    }

    // Enhanced toggle method to include session tracking
    async toggleLamp() {
        if (this.isAnimating) return;

        this.isAnimating = true;

        try {
            // Generate or reuse session ID
            if (!this.sessionId) {
                this.sessionId = 'sess_' + Date.now() + '_' + LampApp.generateSecureRandomString(12);
            }

            const response = await fetch('/api/v1/lamp/toggle', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-Session-ID': this.sessionId
                }
            });

            if (response.ok) {
                const data = await response.json();
                // Use unified UI update (adds classes, animations, particles, title)
                this.updateLampFromAPI(data);
                // Refresh dashboard for instant stats update
                this.loadDashboard();
            } else {
                console.error('Toggle failed:', response.status);
                // Fallback to local visual toggle
                this.toggleLampLocal();
            }
        } catch (error) {
            console.error('Toggle error:', error);
            this.toggleLampLocal();
        } finally {
            setTimeout(() => {
                this.isAnimating = false;
            }, 800);
        }
    }

}

// Ensure Anime.js is loaded before using it
if (typeof anime === 'undefined') {
    console.error('Anime.js is not loaded. Animations will not work.');
} else {
    document.addEventListener('DOMContentLoaded', () => {
        if (!window.lampApp) {
            window.lampApp = new LampApp();
        }
    });
}
