// Lamp Interactive App - Enhanced Hanging Lamp Version
class LampApp {
    constructor() {
        this.lamp = document.getElementById('lamp');
        this.stringHandle = document.getElementById('stringHandle');
        this.stringPath = document.getElementById('stringPath');
        this.stringHighlight = document.getElementById('stringHighlight');
        this.stringSvg = document.querySelector('.string-svg');
        this.html = document.documentElement;
        this.particlesContainer = document.getElementById('particles');
        
        this.isOn = false;
        this.particles = [];
        this.isAnimating = false;
        
        // Spaghetti string physics
        this.isDragging = false;
        this.dragStartY = 0;
        this.dragStartX = 0;
        this.currentPull = 0;
        this.currentSway = 0;
        this.velocity = { x: 0, y: 0 };
        this.pullThreshold = 50;
        this.maxPull = 150;
        this.maxSway = 80;
        this.springForce = 0.12;
        this.damping = 0.88;
        this.isRecoiling = false;
        
        // String curve physics - multiple control points for spaghetti effect
        this.stringPoints = [
            { x: 60, y: 0, vx: 0, vy: 0 },   // Top (fixed)
            { x: 60, y: 20, vx: 0, vy: 0 },  // Control point 1
            { x: 60, y: 40, vx: 0, vy: 0 },  // Control point 2
            { x: 60, y: 60, vx: 0, vy: 0 },  // Control point 3
            { x: 60, y: 80, vx: 0, vy: 0 }   // Bottom (handle attachment)
        ];
        
        this.init();
    }
    
    init() {
        this.bindEvents();
        this.createParticles();
        
        // Initialize string and handle positions
        this.updateStringCurve();
        this.updateHandlePosition();
        
        // Sync with backend state on load
        this.syncWithBackend();
        
        // Load dashboard data
        this.loadDashboard();
        
        // Periodic sync and dashboard updates
        setInterval(() => {
            this.syncWithBackend();
            this.loadDashboard();
        }, 30000); // Update every 30 seconds
        
        // Also update position after DOM is fully ready (as backup)
        requestAnimationFrame(() => {
            this.updateHandlePosition();
        });
        
        // Add entrance animation
        this.animateEntrance();
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
        const stringSvg = this.stringSvg;
        const stringHandle = this.stringHandle;
        
        // Mouse events for both SVG string and handle
        [stringSvg, stringHandle].forEach(element => {
            element.addEventListener('mousedown', (e) => this.startDrag(e));
        });
        
        document.addEventListener('mousemove', (e) => this.onDrag(e));
        document.addEventListener('mouseup', (e) => this.endDrag(e));
        
        // Touch events for both SVG string and handle
        [stringSvg, stringHandle].forEach(element => {
            element.addEventListener('touchstart', (e) => this.startDrag(e), { passive: false });
        });
        
        document.addEventListener('touchmove', (e) => this.onDrag(e), { passive: false });
        document.addEventListener('touchend', (e) => this.endDrag(e));
        
        // Prevent context menu on string elements
        [stringSvg, stringHandle].forEach(element => {
            element.addEventListener('contextmenu', (e) => e.preventDefault());
        });
    }
    
    startDrag(e) {
        e.preventDefault();
        this.isDragging = true;
        this.isRecoiling = false;
        
        const clientY = e.touches ? e.touches[0].clientY : e.clientY;
        const clientX = e.touches ? e.touches[0].clientX : e.clientX;
        
        this.dragStartY = clientY;
        this.dragStartX = clientX;
        this.velocity = { x: 0, y: 0 };
        
        this.stringSvg.style.cursor = 'grabbing';
        this.stringHandle.classList.add('dragging');
        
        document.body.style.userSelect = 'none';
        document.body.style.cursor = 'grabbing';
    }
    
    onDrag(e) {
        if (!this.isDragging) return;
        
        e.preventDefault();
        
        const clientY = e.touches ? e.touches[0].clientY : e.clientY;
        const clientX = e.touches ? e.touches[0].clientX : e.clientX;
        
        const deltaY = clientY - this.dragStartY;
        const deltaX = clientX - this.dragStartX;
        
        // Calculate realistic pull and sway
        this.currentPull = Math.max(0, Math.min(deltaY, this.maxPull));
        this.currentSway = Math.max(-this.maxSway, Math.min(deltaX * 0.8, this.maxSway));
        
        // Update velocity for momentum
        this.velocity.y = deltaY * 0.08;
        this.velocity.x = deltaX * 0.08;
        
        this.updateStringCurve();
        this.updateHandlePosition();
        
        // Visual feedback - update SVG handle size based on pull intensity
        if (this.currentPull > this.pullThreshold * 0.6) {
            const intensity = Math.min(this.currentPull / this.maxPull, 1);
            // Scale the handle slightly based on pull intensity
            const baseScale = 1 + (this.currentPull / this.maxPull) * 0.1;
            const intensityScale = 1 + intensity * 0.05;
            
            // Update the transform to include intensity scaling
            const lastPoint = this.stringPoints[this.stringPoints.length - 1];
            const rotation = this.currentSway * 0.1;
            const totalScale = baseScale * intensityScale;
            
            this.stringHandle.setAttribute('transform', 
                `rotate(${rotation} ${lastPoint.x} ${lastPoint.y}) scale(${totalScale} ${totalScale})`
            );
        }
    }
    
    updateStringCurve() {
        // Reset points to original positions
        this.stringPoints = [
            { x: 60, y: 0, vx: 0, vy: 0 },   // Top (fixed)
            { x: 60, y: 20, vx: 0, vy: 0 },  
            { x: 60, y: 40, vx: 0, vy: 0 },  
            { x: 60, y: 60, vx: 0, vy: 0 },  
            { x: 60, y: 80, vx: 0, vy: 0 }   // Bottom
        ];
        
        // Apply forces to create spaghetti-like curves
        const forceStrength = this.currentPull / this.maxPull;
        
        // Each point gets influenced by the drag with increasing effect down the string
        for (let i = 1; i < this.stringPoints.length; i++) {
            const influence = Math.pow(i / (this.stringPoints.length - 1), 1.5);
            
            // Vertical displacement (pull down)
            this.stringPoints[i].y += this.currentPull * influence * 0.4;
            
            // Horizontal displacement (sway) with natural curve
            const swayOffset = this.currentSway * influence * 0.6;
            const curveOffset = Math.sin(i * 0.8) * swayOffset * 0.3; // Natural curve
            this.stringPoints[i].x += swayOffset + curveOffset;
            
            // Add some natural droop between points
            if (i > 1) {
                const droopAmount = forceStrength * 15 * Math.sin(i * 0.5);
                this.stringPoints[i].y += droopAmount;
            }
        }
        
        // Create smooth curved path using quadratic Bezier curves
        let pathData = `M ${this.stringPoints[0].x} ${this.stringPoints[0].y}`;
        
        for (let i = 1; i < this.stringPoints.length - 1; i++) {
            const cp1x = this.stringPoints[i].x;
            const cp1y = this.stringPoints[i].y;
            const cp2x = this.stringPoints[i + 1].x;
            const cp2y = this.stringPoints[i + 1].y;
            
            pathData += ` Q ${cp1x} ${cp1y} ${cp2x} ${cp2y}`;
        }
        
        // Update both the main path and highlight
        this.stringPath.setAttribute('d', pathData);
        this.stringHighlight.setAttribute('d', pathData);
    }
    
    updateHandlePosition() {
        // Position SVG handle at the end of the string curve
        const lastPoint = this.stringPoints[this.stringPoints.length - 1];
        
        // Since handle is now an SVG element, we can directly set its position
        // in SVG coordinate space
        this.stringHandle.setAttribute('cx', lastPoint.x);
        this.stringHandle.setAttribute('cy', lastPoint.y);
        
        // Apply rotation and scaling effects
        const rotation = this.currentSway * 0.1;
        const scale = 1 + (this.currentPull / this.maxPull) * 0.1;
        
        // Apply transform for rotation and scaling around the handle center
        this.stringHandle.setAttribute('transform', 
            `rotate(${rotation} ${lastPoint.x} ${lastPoint.y}) scale(${scale} ${scale})`
        );
    }
    
    endDrag(e) {
        if (!this.isDragging) return;
        
        this.isDragging = false;
        document.body.style.userSelect = '';
        document.body.style.cursor = '';
        
        this.stringSvg.style.cursor = 'grab';
        this.stringHandle.classList.remove('dragging');
        
        // Check if pulled enough to trigger lamp toggle
        if (this.currentPull >= this.pullThreshold) {
            this.triggerPullAnimation();
        } else {
            // Start realistic spaghetti-like recoil
            this.startSpaghettiRecoil();
        }
    }
    
    startSpaghettiRecoil() {
        this.isRecoiling = true;
        this.animateSpaghettiRecoil();
    }
    
    animateSpaghettiRecoil() {
        if (!this.isRecoiling) return;
        
        // Apply spring forces to each point independently
        for (let i = 1; i < this.stringPoints.length; i++) {
            const targetX = 60;
            const targetY = i * 20;
            
            // Calculate spring forces
            const forceX = (targetX - this.stringPoints[i].x) * this.springForce;
            const forceY = (targetY - this.stringPoints[i].y) * this.springForce;
            
            // Update velocity
            this.stringPoints[i].vx += forceX;
            this.stringPoints[i].vy += forceY;
            
            // Apply damping
            this.stringPoints[i].vx *= this.damping;
            this.stringPoints[i].vy *= this.damping;
            
            // Update position
            this.stringPoints[i].x += this.stringPoints[i].vx;
            this.stringPoints[i].y += this.stringPoints[i].vy;
        }
        
        // Apply overall pull and sway forces
        const pullForce = -this.currentPull * this.springForce * 0.5;
        const swayForce = -this.currentSway * this.springForce * 0.5;
        
        this.velocity.y += pullForce;
        this.velocity.x += swayForce;
        this.velocity.y *= this.damping;
        this.velocity.x *= this.damping;
        
        this.currentPull += this.velocity.y;
        this.currentSway += this.velocity.x;
        
        // Constrain bounds
        this.currentPull = Math.max(-30, Math.min(this.maxPull, this.currentPull));
        this.currentSway = Math.max(-this.maxSway, Math.min(this.maxSway, this.currentSway));
        
        // Update visual
        this.updateStringCurve();
        this.updateHandlePosition();
        
        // Continue if there's still movement
        const totalMovement = Math.abs(this.velocity.y) + Math.abs(this.velocity.x) + 
                            Math.abs(this.currentPull) + Math.abs(this.currentSway);
        
        if (totalMovement > 2) {
            requestAnimationFrame(() => this.animateSpaghettiRecoil());
        } else {
            this.finishSpaghettiRecoil();
        }
    }
    
    finishSpaghettiRecoil() {
        this.isRecoiling = false;
        this.velocity = { x: 0, y: 0 };
        
        // Smooth snap back to original position
        if (typeof anime !== 'undefined') {
            anime({
                targets: { pull: this.currentPull, sway: this.currentSway },
                pull: 0,
                sway: 0,
                duration: 500,
                easing: 'easeOutElastic(1, 0.8)',
                update: (anim) => {
                    this.currentPull = anim.animations[0].currentValue;
                    this.currentSway = anim.animations[1].currentValue;
                    this.updateStringCurve();
                    this.updateHandlePosition();
                },
                complete: () => {
                    this.resetStringPosition();
                }
            });
        } else {
            this.resetStringPosition();
        }
    }
    
    triggerPullAnimation() {
        this.isRecoiling = false;
        
        // Dramatic pull with spaghetti overshoot
        if (typeof anime !== 'undefined') {
            anime({
                targets: { pull: this.currentPull, sway: this.currentSway },
                pull: this.currentPull + 25,
                sway: this.currentSway * 1.3,
                duration: 120,
                easing: 'easeOutQuad',
                update: (anim) => {
                    this.currentPull = anim.animations[0].currentValue;
                    this.currentSway = anim.animations[1].currentValue;
                    this.updateStringCurve();
                    this.updateHandlePosition();
                },
                complete: () => {
                    // Spaghetti-like recoil with multiple bounces
                    anime({
                        targets: { pull: this.currentPull + 25, sway: this.currentSway * 1.3 },
                        pull: [this.currentPull + 25, -20, 15, -8, 3, 0],
                        sway: [this.currentSway * 1.3, this.currentSway * -0.4, this.currentSway * 0.2, this.currentSway * -0.1, 0],
                        duration: 1000,
                        easing: 'easeOutElastic(1, 0.6)',
                        update: (anim) => {
                            this.currentPull = anim.animations[0].currentValue;
                            this.currentSway = anim.animations[1].currentValue;
                            this.updateStringCurve();
                            this.updateHandlePosition();
                        },
                        complete: () => {
                            this.resetStringPosition();
                        }
                    });
                }
            });
        } else {
            setTimeout(() => this.resetStringPosition(), 800);
        }
        
        // Toggle lamp
        setTimeout(() => {
            this.toggleLampState();
        }, 80);
    }
    
    resetStringPosition() {
        // Reset SVG path to original straight line
        const originalPath = 'M 60 0 Q 60 20 60 40 Q 60 60 60 80';
        this.stringPath.setAttribute('d', originalPath);
        this.stringHighlight.setAttribute('d', originalPath);
        
        // Reset handle position to original position in SVG coordinates
        this.stringHandle.setAttribute('cx', '60');
        this.stringHandle.setAttribute('cy', '80');
        this.stringHandle.removeAttribute('transform');
        
        // Reset physics state
        this.currentPull = 0;
        this.currentSway = 0;
        this.velocity = { x: 0, y: 0 };
        this.isRecoiling = false;
        
        // Reset string points
        this.stringPoints = [
            { x: 60, y: 0, vx: 0, vy: 0 },
            { x: 60, y: 20, vx: 0, vy: 0 },
            { x: 60, y: 40, vx: 0, vy: 0 },
            { x: 60, y: 60, vx: 0, vy: 0 },
            { x: 60, y: 80, vx: 0, vy: 0 }
        ];
    }
    
    toggleLampState() {
        // Call the API to toggle the lamp
        this.callToggleAPI();
    }

    async callToggleAPI() {
        try {
            const response = await fetch('/api/v1/lamp/toggle', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                }
            });
            
            if (response.ok) {
                const data = await response.json();
                // Update the lamp state based on API response
                this.updateLampFromAPI(data);
            } else {
                // Fallback to local toggle if API fails
                this.toggleLampLocal();
            }
        } catch (error) {
            // Fallback to local toggle if API fails
            this.toggleLampLocal();
        }
    }

    updateLampFromAPI(data) {
        // Update lamp state from API response
        this.isOn = data.is_on;
        
        // Update lamp classes
        this.lamp.classList.toggle('on', this.isOn);
        this.lamp.classList.toggle('off', !this.isOn);
        
        // Animate lamp swinging
        this.animateLampSwing();
        
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
        
        // Update lamp classes
        this.lamp.classList.toggle('on', this.isOn);
        this.lamp.classList.toggle('off', !this.isOn);
        
        // Animate lamp swinging
        this.animateLampSwing();
        
        // Update theme
        this.updateTheme();
        
        // Trigger particle effects
        if (this.isOn) {
            this.triggerLightParticles();
        }
    }
    
    // This method is now replaced by the enhanced async version below
    
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
        
        // Add subtle bounce when turning on
        if (this.isOn) {
            anime({
                targets: '.light-glow',
                scale: [0.5, 1.2, 1],
                opacity: [0, 1, 1],
                duration: 800,
                easing: 'easeOutElastic(1, 0.4)'
            });
            
            // Animate the bulb glow
            anime({
                targets: '.bulb-glass',
                scale: [1, 1.05, 1],
                duration: 600,
                easing: 'easeOutElastic(1, 0.3)'
            });
        } else {
            // Fade out the glow
            anime({
                targets: '.light-glow',
                opacity: [1, 0],
                duration: 400,
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
                // Set initial state from backend without animation
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
        try {
            const response = await fetch('/api/v1/lamp/dashboard');
            if (response.ok) {
                const data = await response.json();
                this.updateDashboard(data);
            }
        } catch (error) {
            console.warn('Dashboard update failed:', error);
        }
    }
    
    updateDashboard(data) {
        // Update current state
        const currentStateEl = document.getElementById('currentState');
        if (currentStateEl) {
            currentStateEl.textContent = data.current_state.is_on ? '🔥 ON' : '🌙 OFF';
            currentStateEl.style.color = data.current_state.is_on ? '#f1c40f' : '#95a5a6';
        }
        
        // Update today's toggles
        const todayTogglesEl = document.getElementById('todayToggles');
        if (todayTogglesEl) {
            todayTogglesEl.textContent = data.today_stats ? data.today_stats.total_toggles : '0';
        }
        
        // Update lifetime toggles
        const lifetimeTogglesEl = document.getElementById('lifetimeToggles');
        if (lifetimeTogglesEl) {
            lifetimeTogglesEl.textContent = data.total_lifetime_toggles.toLocaleString();
        }
        
        // Update unique sessions
        const uniqueSessionsEl = document.getElementById('uniqueSessions');
        if (uniqueSessionsEl) {
            uniqueSessionsEl.textContent = data.today_stats ? data.today_stats.unique_sessions : '0';
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
                this.sessionId = 'sess_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
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
                this.isOn = data.is_on;
                
                // Update UI immediately
                this.updateTheme();
                document.title = `Lamp App - ${data.status.toUpperCase()}`;
                
                // Refresh dashboard data after a short delay
                setTimeout(() => {
                    this.loadDashboard();
                }, 1000);
                
            } else {
                console.error('Toggle failed:', response.status);
            }
        } catch (error) {
            console.error('Toggle error:', error);
        } finally {
            setTimeout(() => {
                this.isAnimating = false;
            }, 800);
        }
    }

}

// Initialize app when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    if (!window.lampApp) {
        window.lampApp = new LampApp();
        
        // Create some floating particles periodically
        setInterval(() => {
            if (window.lampApp && window.lampApp.particles.length < 30) {
                window.lampApp.createParticle();
            }
        }, 2000);
    }
});
