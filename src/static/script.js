// Lamp Interactive App - Enhanced Hanging Lamp Version
class LampApp {
    constructor() {
        // DOM elements
        this.lamp = document.getElementById('lamp');
        this.stringHandle = document.getElementById('stringHandle');
        this.stringPath = document.getElementById('stringPath');
        this.stringHighlight = document.getElementById('stringHighlight');
        this.stringSvg = document.querySelector('.string-svg');
        this.html = document.documentElement;
        this.particlesContainer = document.getElementById('particles');

        // State
        this.isOn = false;
        this.isAnimating = false;
        this.isDragging = false;
        this.isRecoiling = false;
        this.particles = [];
        this.eventCleanup = [];

        // Physics
        this.physics = { pullThreshold: 50, maxPull: 150, maxSway: 80, springForce: 0.12, damping: 0.88 };
        this.dragStart = { x: 0, y: 0 };
        this.current = { pull: 0, sway: 0 };
        this.velocity = { x: 0, y: 0 };

        // String points
        this.stringPoints = [
            { x: 60, y: 0, vx: 0, vy: 0 }, { x: 60, y: 20, vx: 0, vy: 0 }, { x: 60, y: 40, vx: 0, vy: 0 },
            { x: 60, y: 60, vx: 0, vy: 0 }, { x: 60, y: 80, vx: 0, vy: 0 }
        ];

        this.init();
    }

    init() {
        console.log('🚀 LampApp initializing...');
        this.bindEvents();
        this.createParticles();
        this.updateStringCurve();
        this.updateHandlePosition();
        this.isOn = this.lamp.classList.contains('on');
        console.log('Initial lamp state:', this.isOn);

        this.startUpdateLoop();
        this.animateEntrance();

        // Force dashboard load after a short delay to ensure DOM is ready
        setTimeout(() => {
            console.log('🔧 Force loading dashboard after delay...');
            this.loadDashboard();

            // Direct test of DOM elements
            console.log('🧪 Testing direct DOM manipulation...');
            const testEl = document.getElementById('todayToggles');
            if (testEl) {
                testEl.textContent = 'TEST';
                console.log('✅ Direct DOM test successful');
            } else {
                console.error('❌ Direct DOM test failed - element not found');
            }
        }, 1000);

        console.log('✅ LampApp initialization complete');
    }

    startUpdateLoop() {
        console.log('🔄 Setting up update loop...');

        // Load dashboard immediately
        this.loadDashboard();

        // Set up periodic updates
        this.updateInterval = setInterval(() => {
            console.log('⏰ Periodic update starting...');
            this.syncWithBackend();
            this.loadDashboard();
            if (this.particles.length < 30) this.createParticle();
        }, 5000);  // More frequent updates for better responsiveness

        requestAnimationFrame(() => this.updateHandlePosition());
    }

    bindEvents() {
        if (this.lamp) {
            const click = (e) => !e.target.closest('.pull-string-container') && (e.preventDefault(), this.toggleLampState());
            const keydown = (e) => (['Enter', ' '].includes(e.key)) && (e.preventDefault(), this.toggleLampState());
            this.lamp.addEventListener('click', click);
            this.lamp.addEventListener('keydown', keydown);
            this.eventCleanup.push(() => this.lamp.removeEventListener('click', click), () => this.lamp.removeEventListener('keydown', keydown));
        }

        this.bindStringDragEvents();

        const globalKey = (e) => ['l', 'L'].includes(e.key) && this.toggleLampState();
        const saveState = () => localStorage.setItem('lampState', JSON.stringify({ isOn: this.isOn }));

        document.addEventListener('keydown', globalKey);
        window.addEventListener('beforeunload', saveState);
        this.eventCleanup.push(() => document.removeEventListener('keydown', globalKey), () => window.removeEventListener('beforeunload', saveState));

        this.loadState();
    }

    bindStringDragEvents() {
        const elements = [this.stringSvg, this.stringHandle].filter(Boolean);
        const handlers = {
            mousedown: (e) => this.startDrag(e),
            touchstart: (e) => this.startDrag(e),
            contextmenu: (e) => e.preventDefault()
        };

        elements.forEach(el => {
            Object.entries(handlers).forEach(([event, handler]) => {
                el.addEventListener(event, handler, event === 'touchstart' ? { passive: false } : undefined);
                this.eventCleanup.push(() => el.removeEventListener(event, handler));
            });
        });

        const globalHandlers = {
            mousemove: (e) => this.onDrag(e),
            mouseup: (e) => this.endDrag(e),
            touchmove: (e) => this.onDrag(e),
            touchend: (e) => this.endDrag(e)
        };

        Object.entries(globalHandlers).forEach(([event, handler]) => {
            document.addEventListener(event, handler, event.includes('touch') ? { passive: false } : undefined);
            this.eventCleanup.push(() => document.removeEventListener(event, handler));
        });
    }

    startDrag(e) {
        e.preventDefault();
        this.isDragging = true;
        this.isRecoiling = false;
        const touch = e.touches?.[0] || e;
        this.dragStart = { x: touch.clientX, y: touch.clientY };
        this.velocity = { x: 0, y: 0 };
        Object.assign(this.stringSvg.style, { cursor: 'grabbing' });
        Object.assign(document.body.style, { userSelect: 'none', cursor: 'grabbing' });
        this.stringHandle.classList.add('dragging');
    }

    onDrag(e) {
        if (!this.isDragging) return;
        e.preventDefault();

        const touch = e.touches?.[0] || e;
        const delta = { x: touch.clientX - this.dragStart.x, y: touch.clientY - this.dragStart.y };

        this.current.pull = Math.max(0, Math.min(delta.y, this.physics.maxPull));
        this.current.sway = Math.max(-this.physics.maxSway, Math.min(delta.x * 0.8, this.physics.maxSway));
        this.velocity = { x: delta.x * 0.08, y: delta.y * 0.08 };

        this.updateStringCurve();
        this.updateHandlePosition();

        if (this.current.pull > this.physics.pullThreshold * 0.6) {
            const intensity = this.current.pull / this.physics.maxPull;
            const scale = 1 + intensity * 0.15;
            const lastPoint = this.stringPoints[this.stringPoints.length - 1];
            this.stringHandle.setAttribute('transform', `rotate(${this.current.sway * 0.1} ${lastPoint.x} ${lastPoint.y}) scale(${scale})`);
        }
    }

    updateStringCurve() {
        this.stringPoints = Array.from({length: 5}, (_, i) => ({ x: 60, y: i * 20, vx: 0, vy: 0 }));

        const forceStrength = this.current.pull / this.physics.maxPull;
        let pathData = `M 60 0`;

        for (let i = 1; i < 5; i++) {
            const influence = Math.pow(i / 4, 1.5);
            const point = this.stringPoints[i];

            point.y += this.current.pull * influence * 0.4;
            const swayOffset = this.current.sway * influence * 0.6;
            point.x += swayOffset + Math.sin(i * 0.8) * swayOffset * 0.3;

            if (i > 1) point.y += forceStrength * 15 * Math.sin(i * 0.5);
            if (i < 4) pathData += ` Q ${point.x} ${point.y} ${this.stringPoints[i + 1].x} ${this.stringPoints[i + 1].y}`;
        }

        this.stringPath.setAttribute('d', pathData);
        this.stringHighlight.setAttribute('d', pathData);
    }

    updateHandlePosition() {
        const lastPoint = this.stringPoints[4];
        Object.assign(this.stringHandle, {
            cx: lastPoint.x,
            cy: lastPoint.y,
            transform: `rotate(${this.current.sway * 0.1} ${lastPoint.x} ${lastPoint.y}) scale(${1 + (this.current.pull / this.physics.maxPull) * 0.1})`
        });
    }

    endDrag(e) {
        if (!this.isDragging) return;
        this.isDragging = false;
        Object.assign(document.body.style, { userSelect: '', cursor: '' });
        this.stringSvg.style.cursor = 'grab';
        this.stringHandle.classList.remove('dragging');

        this.current.pull >= this.physics.pullThreshold ? this.triggerPullAnimation() : this.startSpaghettiRecoil();
    }

    startSpaghettiRecoil() {
        this.isRecoiling = true;
        this.animateSpaghettiRecoil();
    }

    animateSpaghettiRecoil() {
        if (!this.isRecoiling) return;

        for (let i = 1; i < 5; i++) {
            const point = this.stringPoints[i];
            const [forceX, forceY] = [(60 - point.x) * this.physics.springForce, (i * 20 - point.y) * this.physics.springForce];

            point.vx = (point.vx + forceX) * this.physics.damping;
            point.vy = (point.vy + forceY) * this.physics.damping;
            point.x += point.vx;
            point.y += point.vy;
        }

        this.velocity.y = (this.velocity.y - this.current.pull * this.physics.springForce * 0.5) * this.physics.damping;
        this.velocity.x = (this.velocity.x - this.current.sway * this.physics.springForce * 0.5) * this.physics.damping;

        this.current.pull = Math.max(-30, Math.min(this.physics.maxPull, this.current.pull + this.velocity.y));
        this.current.sway = Math.max(-this.physics.maxSway, Math.min(this.physics.maxSway, this.current.sway + this.velocity.x));

        this.updateStringCurve();
        this.updateHandlePosition();

        (Math.abs(this.velocity.y) + Math.abs(this.velocity.x) + Math.abs(this.current.pull) + Math.abs(this.current.sway) > 2)
            ? requestAnimationFrame(() => this.animateSpaghettiRecoil())
            : this.finishSpaghettiRecoil();
    }

    finishSpaghettiRecoil() {
        this.isRecoiling = false;
        this.velocity = { x: 0, y: 0 };

        typeof anime !== 'undefined' ? anime({
            targets: { pull: this.current.pull, sway: this.current.sway },
            pull: 0, sway: 0, duration: 500, easing: 'easeOutElastic(1, 0.8)',
            update: anim => {
                this.current.pull = anim.animations[0].currentValue;
                this.current.sway = anim.animations[1].currentValue;
                this.updateStringCurve();
                this.updateHandlePosition();
            },
            complete: () => this.resetStringPosition()
        }) : this.resetStringPosition();
    }

    triggerPullAnimation() {
        this.isRecoiling = false;

        if (typeof anime !== 'undefined') {
            anime({
                targets: { pull: this.current.pull, sway: this.current.sway },
                pull: this.current.pull + 25, sway: this.current.sway * 1.3,
                duration: 120, easing: 'easeOutQuad',
                update: anim => {
                    this.current.pull = anim.animations[0].currentValue;
                    this.current.sway = anim.animations[1].currentValue;
                    this.updateStringCurve();
                    this.updateHandlePosition();
                },
                complete: () => anime({
                    targets: { pull: this.current.pull + 25, sway: this.current.sway * 1.3 },
                    pull: [this.current.pull + 25, -20, 15, -8, 3, 0],
                    sway: [this.current.sway * 1.3, this.current.sway * -0.4, this.current.sway * 0.2, this.current.sway * -0.1, 0],
                    duration: 1000, easing: 'easeOutElastic(1, 0.6)',
                    update: anim => {
                        this.current.pull = anim.animations[0].currentValue;
                        this.current.sway = anim.animations[1].currentValue;
                        this.updateStringCurve();
                        this.updateHandlePosition();
                    },
                    complete: () => this.resetStringPosition()
                })
            });
        } else {
            setTimeout(() => this.resetStringPosition(), 800);
        }

        setTimeout(() => this.toggleLampState(), 80);
    }

    resetStringPosition() {
        const originalPath = 'M 60 0 Q 60 20 60 40 Q 60 60 60 80';
        this.stringPath.setAttribute('d', originalPath);
        this.stringHighlight.setAttribute('d', originalPath);

        Object.assign(this.stringHandle, { cx: '60', cy: '80' });
        this.stringHandle.removeAttribute('transform');

        Object.assign(this, {
            current: { pull: 0, sway: 0 },
            velocity: { x: 0, y: 0 },
            isRecoiling: false,
            stringPoints: Array.from({length: 5}, (_, i) => ({ x: 60, y: i * 20, vx: 0, vy: 0 }))
        });
    }

    toggleLampState() {
        if (this.isAnimating) return;

        console.log('🎯 Lamp clicked! Toggling state...');
        this.isAnimating = true;
        this.isOn = !this.isOn;
        this.updateLampVisuals();
        this.callToggleAPI();
    }

    async callToggleAPI() {
        try {
            const response = await fetch('/api/v1/lamp/toggle', { method: 'POST', headers: { 'Content-Type': 'application/json' } });
            if (response.ok) {
                const data = await response.json();
                if (data.is_on !== this.isOn) {
                    this.isOn = data.is_on;
                    this.updateLampVisuals();
                }

                // Immediately update dashboard after successful toggle
                console.log('🔄 Refreshing dashboard after toggle...');
                setTimeout(() => this.loadDashboard(), 100);
            }
        } catch (error) {
            console.warn('API call failed:', error);
        } finally {
            setTimeout(() => this.isAnimating = false, 800);
        }
    }

    updateLampVisuals() {
        this.lamp.classList.remove('on', 'off');
        this.lamp.classList.add(this.isOn ? 'on' : 'off');
        this.lamp.offsetHeight;

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
        document.title = `Lamp App - ${this.isOn ? 'ON' : 'OFF'}`;
    }

    // This method is now replaced by the enhanced async version below

    animateLampSwing() {
        anime({
            targets: this.lamp,
            rotate: [
                { value: -3, duration: 200, easing: 'easeOutQuad' },
                { value: 2, duration: 200, easing: 'easeInOutQuad' },
                { value: -1, duration: 200, easing: 'easeInOutQuad' },
                { value: 0, duration: 300, easing: 'easeOutElastic(1, 0.3)' }
            ]
        });

        if (this.isOn) {
            anime({ targets: '.light-glow', scale: [0.8, 1.1, 1], duration: 600, easing: 'easeOutElastic(1, 0.4)' });
            anime({ targets: '.bulb-glass', scale: [1, 1.08, 1], duration: 500, easing: 'easeOutElastic(1, 0.3)' });
            anime({ targets: '.shade-body', scale: [1, 1.02, 1], duration: 400, easing: 'easeOutQuad' });
        } else {
            anime({ targets: '.light-glow', scale: 1, duration: 300, easing: 'easeOutQuad' });
            anime({ targets: '.bulb-glass', scale: [1, 0.98, 1], duration: 300, easing: 'easeOutQuad' });
            anime({ targets: '.shade-body', scale: 1, duration: 300, easing: 'easeOutQuad' });
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
        // Don't sync if user is currently interacting with the lamp
        if (this.isAnimating) {
            return;
        }

        // Add visual indicator
        document.title = 'Loading... - Lamp App';

        try {
            const response = await fetch('/api/v1/lamp/status');
            if (response.ok) {
                const data = await response.json();

                // Only update if the state actually differs to avoid unnecessary updates
                if (data.is_on !== this.isOn) {
                    console.log(`Syncing backend state: ${data.is_on} (was: ${this.isOn})`);
                    this.isOn = data.is_on;
                    this.updateLampVisuals();
                }

                // Update page title to show sync status
                document.title = `Lamp App - ${data.status.toUpperCase()}`;
            } else {
                document.title = 'Lamp App - API Error';
            }
        } catch (error) {
            document.title = 'Lamp App - No Connection';
        }
    }

    // Manual test function for debugging
    async testDashboard() {
        console.log('🧪 Manual dashboard test...');
        console.log('Elements:', {
            currentState: document.getElementById('currentState'),
            todayToggles: document.getElementById('todayToggles'),
            lifetimeToggles: document.getElementById('lifetimeToggles'),
            uniqueSessions: document.getElementById('uniqueSessions')
        });

        try {
            const response = await fetch('/api/v1/lamp/dashboard');
            const data = await response.json();
            console.log('Test API data:', data);
            this.updateDashboard(data);
        } catch (error) {
            console.error('Test failed:', error);
        }
    }

    // Dashboard methods
    async loadDashboard() {
        console.log('Loading dashboard data...');

        // Debug: Check if elements exist before API call
        console.log('DOM elements check:', {
            currentState: !!document.getElementById('currentState'),
            todayToggles: !!document.getElementById('todayToggles'),
            lifetimeToggles: !!document.getElementById('lifetimeToggles'),
            uniqueSessions: !!document.getElementById('uniqueSessions'),
            activityList: !!document.getElementById('activityList')
        });

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
            console.log('✅ Updated currentState:', currentStateEl.textContent);
        } else {
            console.error('❌ currentState element not found');
        }

        // Update today's toggles
        const todayTogglesEl = document.getElementById('todayToggles');
        if (todayTogglesEl) {
            todayTogglesEl.textContent = data.today_stats ? data.today_stats.total_toggles : '0';
            console.log('✅ Updated todayToggles:', todayTogglesEl.textContent);
        } else {
            console.error('❌ todayToggles element not found');
        }

        // Update lifetime toggles
        const lifetimeTogglesEl = document.getElementById('lifetimeToggles');
        if (lifetimeTogglesEl) {
            lifetimeTogglesEl.textContent = data.total_lifetime_toggles.toLocaleString();
            console.log('✅ Updated lifetimeToggles:', lifetimeTogglesEl.textContent);
        } else {
            console.error('❌ lifetimeToggles element not found');
        }

        // Update unique sessions
        const uniqueSessionsEl = document.getElementById('uniqueSessions');
        if (uniqueSessionsEl) {
            uniqueSessionsEl.textContent = data.today_stats ? data.today_stats.unique_sessions : '0';
            console.log('✅ Updated uniqueSessions:', uniqueSessionsEl.textContent);
        } else {
            console.error('❌ uniqueSessions element not found');
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

    // Cleanup method for proper memory management
    destroy() {
        // Clear intervals
        if (this.updateInterval) {
            clearInterval(this.updateInterval);
            this.updateInterval = null;
        }

        // Remove all event listeners
        this.eventCleanup.forEach(cleanup => cleanup());
        this.eventCleanup = [];

        // Clear particles
        this.particles.forEach(particle => {
            if (particle.parentNode) {
                particle.remove();
            }
        });
        this.particles = [];

        console.log('LampApp destroyed and cleaned up');
    }

}

// Initialize app when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    console.log('🎯 DOM loaded - starting initialization...');

    // Simple test function
    window.testStats = async () => {
        console.log('🧪 Testing stats display...');
        try {
            const response = await fetch('/api/v1/lamp/dashboard');
            const data = await response.json();
            console.log('📊 Got data:', data);

            // Direct DOM updates
            const elements = {
                currentState: document.getElementById('currentState'),
                todayToggles: document.getElementById('todayToggles'),
                lifetimeToggles: document.getElementById('lifetimeToggles'),
                uniqueSessions: document.getElementById('uniqueSessions')
            };

            console.log('🎯 Elements found:', Object.fromEntries(
                Object.entries(elements).map(([k, v]) => [k, !!v])
            ));

            if (elements.currentState) {
                elements.currentState.textContent = data.current_state.is_on ? '🔥 ON' : '🌙 OFF';
                elements.currentState.style.color = data.current_state.is_on ? '#f1c40f' : '#95a5a6';
                console.log('✅ Updated currentState');
            }
            if (elements.todayToggles) {
                elements.todayToggles.textContent = data.today_stats.total_toggles;
                console.log('✅ Updated todayToggles to:', data.today_stats.total_toggles);
            }
            if (elements.lifetimeToggles) {
                elements.lifetimeToggles.textContent = data.total_lifetime_toggles;
                console.log('✅ Updated lifetimeToggles to:', data.total_lifetime_toggles);
            }
            if (elements.uniqueSessions) {
                elements.uniqueSessions.textContent = data.today_stats.unique_sessions;
                console.log('✅ Updated uniqueSessions to:', data.today_stats.unique_sessions);
            }

            return 'Stats updated successfully!';
        } catch (error) {
            console.error('❌ Test failed:', error);
            return 'Test failed: ' + error.message;
        }
    };

    // Force update stats immediately
    window.forceUpdateStats = () => {
        if (window.lampApp) {
            console.log('🔄 Force updating dashboard...');
            window.lampApp.loadDashboard();
        }
    };    if (!window.lampApp) {
        window.lampApp = new LampApp();

        // Test stats immediately after app initialization
        setTimeout(window.testStats, 2000);

        // Cleanup on page unload
        window.addEventListener('beforeunload', () => {
            if (window.lampApp && typeof window.lampApp.destroy === 'function') {
                window.lampApp.destroy();
            }
        });
    }
});
