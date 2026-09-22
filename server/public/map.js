/**
 * A small slippy map, drawn with images.
 *
 * ## Why this exists rather than a map library
 *
 * The CSP this dashboard serves is `script-src 'self'` with no `connect-src`
 * beyond its own origin, on a page that shows a month of somebody's
 * whereabouts. A WebGL map library would have cost three holes in that header —
 * `connect-src` for its tile requests, `worker-src blob:` for its workers, and
 * in practice a loosened `style-src` — plus a megabyte of vendored code into a
 * server that has no bundler. Tiles requested as plain `<img>` elements need
 * exactly one addition, `img-src https://api.mapbox.com`, and no new
 * executable code at all.
 *
 * ## The referrer trap
 *
 * The site's Mapbox token is URL-restricted, which Mapbox enforces by reading
 * the `Referer` header. This server sets `Referrer-Policy: no-referrer` on
 * every response, so a tile request inherits that, arrives anonymous and is
 * refused with a 403 and no visible error — a blank map and nothing in the
 * console to explain it. Each tile therefore carries its own
 * `referrerpolicy="strict-origin-when-cross-origin"`, which overrides the
 * document policy for that element alone and sends the ORIGIN and nothing more:
 * Mapbox learns it is strangeramblings.com, and never which page or which day
 * was being looked at.
 *
 * Everything degrades: with no token, or a failed fetch, the track draws on a
 * plain ground with a scale bar. A map of where you were is still worth reading
 * without the streets under it.
 */
(function () {
  const TILE = 512;
  const MIN_ZOOM = 2;
  const MAX_ZOOM = 18;
  const MAX_LAT = 85.0511287798;
  const EARTH_CIRCUMFERENCE_M = 40075016.686;
  /** Below this many screen pixels apart, two fixes draw as one point. */
  const MIN_STEP_PX = 2.5;

  const clamp = (value, lo, hi) => Math.min(hi, Math.max(lo, value));
  const worldSize = (zoom) => TILE * 2 ** zoom;

  function project(lng, lat, zoom) {
    const size = worldSize(zoom);
    const sin = Math.sin((clamp(lat, -MAX_LAT, MAX_LAT) * Math.PI) / 180);
    return [
      ((lng + 180) / 360) * size,
      (0.5 - Math.log((1 + sin) / (1 - sin)) / (4 * Math.PI)) * size,
    ];
  }

  function unproject(x, y, zoom) {
    const size = worldSize(zoom);
    const n = Math.PI - (2 * Math.PI * y) / size;
    return [(x / size) * 360 - 180, (180 / Math.PI) * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n)))];
  }

  /** Metres one screen pixel covers, which depends on latitude as well as zoom. */
  function metresPerPixel(lat, zoom) {
    return (EARTH_CIRCUMFERENCE_M * Math.cos((lat * Math.PI) / 180)) / worldSize(zoom);
  }

  /**
   * `mapbox://styles/mapbox/outdoors-v12` is what the credential store hands
   * out, because that is the form a GL map wants. The raster endpoint needs it
   * spelled as a REST path.
   */
  function rasterTemplate(style, token) {
    const match = /^mapbox:\/\/styles\/([^/]+)\/([^/]+)$/.exec(style ?? '');
    if (!match || !token) return null;
    const retina = (window.devicePixelRatio || 1) > 1.5 ? '@2x' : '';
    return `https://api.mapbox.com/styles/v1/${match[1]}/${match[2]}/tiles/${TILE}/{z}/{x}/{y}${retina}?access_token=${encodeURIComponent(token)}`;
  }

  const svg = (name, attributes) => {
    const node = document.createElementNS('http://www.w3.org/2000/svg', name);
    for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, value);
    return node;
  };

  function create(container, { onCursorChange = null } = {}) {
    container.classList.add('map-frame');
    container.tabIndex = 0;
    container.setAttribute('role', 'application');
    container.setAttribute('aria-label', 'Map of recorded movement. Drag to pan, arrow keys to move, plus and minus to zoom.');

    const tileLayer = document.createElement('div');
    tileLayer.className = 'map-tiles';
    const overlay = svg('svg', { class: 'map-overlay' });
    const scaleBar = document.createElement('div');
    scaleBar.className = 'map-scale';
    const attribution = document.createElement('div');
    attribution.className = 'map-attrib';
    const hint = document.createElement('div');
    hint.className = 'map-hint';
    hint.textContent = 'Click the map to zoom';
    container.append(tileLayer, overlay, scaleBar, attribution, hint);

    const state = { lng: 0, lat: 51, zoom: 12 };
    /** key -> { img, z, x, y }. Tiles from the previous zoom are kept briefly
     *  so a zoom shows the old level stretched rather than a blank frame. */
    const tiles = new Map();
    let template = null;
    let track = { points: [], segments: [], colours: null, gapSeconds: 600 };
    let cursor = null;
    let zoomEnabled = false;
    let lastZoomChange = 0;
    let destroyed = false;
    const pointers = new Map();
    let pinch = null;

    function setAttribution(live) {
      attribution.replaceChildren();
      if (!live) {
        attribution.append(Object.assign(document.createElement('span'), { textContent: 'No map imagery — track and scale only' }));
        return;
      }
      for (const [text, href] of [['© Mapbox', 'https://www.mapbox.com/about/maps/'], ['© OpenStreetMap', 'https://www.openstreetmap.org/copyright']]) {
        const link = document.createElement('a');
        link.textContent = text;
        link.href = href;
        link.target = '_blank';
        link.rel = 'noopener noreferrer';
        attribution.append(link);
      }
    }
    setAttribution(false);

    // ---- tiles ----------------------------------------------------------

    function tileFor(z, x, y) {
      const key = `${z}/${x}/${y}`;
      let tile = tiles.get(key);
      if (tile) return tile;
      const img = document.createElement('img');
      img.className = 'map-tile';
      img.alt = '';
      img.decoding = 'async';
      img.loading = 'eager';
      // Overrides the document's `no-referrer` for this element only. Without
      // it the URL-restricted token 403s and the map is silently blank.
      img.referrerPolicy = 'strict-origin-when-cross-origin';
      img.src = template.replace('{z}', z).replace('{x}', x).replace('{y}', y);
      img.addEventListener('error', () => { img.classList.add('map-tile-failed'); });
      tile = { img, z, x, y };
      tiles.set(key, tile);
      tileLayer.append(img);
      return tile;
    }

    function drawTiles(width, height, originX, originY) {
      if (!template) {
        for (const tile of tiles.values()) tile.img.remove();
        tiles.clear();
        return;
      }
      const tz = clamp(Math.round(state.zoom), MIN_ZOOM, MAX_ZOOM);
      const factor = 2 ** (state.zoom - tz);
      const size = TILE * factor;
      const span = 2 ** tz;
      for (let x = Math.floor(originX / size); x <= Math.floor((originX + width) / size); x++) {
        for (let y = Math.floor(originY / size); y <= Math.floor((originY + height) / size); y++) {
          // Wrap east-west so panning past the date line shows map rather than
          // void; there is nothing above the pole to wrap to, so y is dropped.
          if (y >= 0 && y < span) tileFor(tz, ((x % span) + span) % span, y);
        }
      }
      // A tile from the zoom we just left is kept for a moment and drawn
      // stretched underneath, so zooming shows a blurry map rather than a hole.
      const settled = performance.now() - lastZoomChange > 450;
      const worldSpan = worldSize(state.zoom);
      for (const [key, tile] of tiles) {
        const tileSize = TILE * 2 ** (state.zoom - tile.z);
        // A wrapped tile is positioned at whichever copy of the world is on
        // screen, so one image serves both sides of the date line.
        let left = tile.x * tileSize - originX;
        while (left > width) left -= worldSpan;
        while (left + tileSize < 0) left += worldSpan;
        const top = tile.y * tileSize - originY;
        const onScreen = left < width + tileSize && left + tileSize > -tileSize && top < height + tileSize && top + tileSize > -tileSize;
        if (!onScreen || (tile.z !== tz && settled)) {
          tile.img.remove();
          tiles.delete(key);
          continue;
        }
        tile.img.style.left = `${left}px`;
        tile.img.style.top = `${top}px`;
        // The extra pixel hides the hairline seams fractional scaling leaves
        // between neighbouring tiles.
        tile.img.style.width = `${tileSize + 1}px`;
        tile.img.style.height = `${tileSize + 1}px`;
        tile.img.style.zIndex = String(tile.z);
      }
    }

    // ---- overlay --------------------------------------------------------

    function screenPoints(width, height, originX, originY) {
      const out = [];
      for (const point of track.points) {
        const [x, y] = project(point[0], point[1], state.zoom);
        out.push([x - originX, y - originY]);
      }
      return out;
    }

    function drawOverlay(width, height, originX, originY) {
      overlay.replaceChildren();
      overlay.setAttribute('viewBox', `0 0 ${width} ${height}`);
      overlay.setAttribute('width', width);
      overlay.setAttribute('height', height);
      if (!track.points.length) return;
      const screen = screenPoints(width, height, originX, originY);
      // Two groups rather than per-element opacity: selecting one activity dims
      // the rest of the day to context without hiding it, and the drawing code
      // below only has to choose a parent.
      const dimmed = svg('g', { class: 'trace-dimmed' });
      const lit = svg('g', {});
      overlay.append(dimmed, lit);
      const inFocus = (i) => !track.focus || (i >= track.focus[0] && i <= track.focus[1]);

      // Gaps first, underneath everything: a dashed hop from where recording
      // stopped to where it started again. Never a solid line — the phone was
      // asleep, and whatever route was taken in between is not known.
      for (let i = 1; i < track.segments.length; i++) {
        const from = screen[track.segments[i - 1][1]];
        const to = screen[track.segments[i][0]];
        const parent = inFocus(track.segments[i - 1][1]) && inFocus(track.segments[i][0]) ? lit : dimmed;
        parent.append(svg('line', { class: 'trace-gap', x1: from[0], y1: from[1], x2: to[0], y2: to[1] }));
      }

      for (const [start, end] of track.segments) {
        // Thin the trace to what the current zoom can actually show. A burst of
        // fixes 30 seconds apart is dozens of points inside one pixel.
        const kept = [start];
        for (let i = start + 1; i <= end; i++) {
          const last = screen[kept[kept.length - 1]];
          const here = screen[i];
          if (i === end || Math.hypot(here[0] - last[0], here[1] - last[1]) >= MIN_STEP_PX) kept.push(i);
        }
        if (kept.length < 2) {
          const [x, y] = screen[start];
          (inFocus(start) ? lit : dimmed).append(svg('circle', { class: 'trace-lone', cx: x, cy: y, r: 4 }));
          continue;
        }
        const draw = (indices, parent) => {
          const d = indices.map((i, n) => `${n ? 'L' : 'M'}${screen[i][0].toFixed(1)} ${screen[i][1].toFixed(1)}`).join('');
          // A casing under the trace, because an orange line on an orange-brown
          // outdoors basemap is legible in a screenshot and not on a hillside.
          parent.append(svg('path', { class: 'trace-casing', d }));
          if (!track.colours) {
            parent.append(svg('path', { class: 'trace', d }));
            return;
          }
          for (let n = 1; n < indices.length; n++) {
            const a = screen[indices[n - 1]];
            const b = screen[indices[n]];
            parent.append(svg('path', {
              class: 'trace',
              stroke: track.colours[indices[n]] ?? track.colours[indices[n - 1]] ?? 'currentColor',
              d: `M${a[0].toFixed(1)} ${a[1].toFixed(1)}L${b[0].toFixed(1)} ${b[1].toFixed(1)}`,
            }));
          }
        };
        // Split wherever the trace crosses the focus boundary: a selected
        // activity is usually part of a longer run of continuous recording.
        let run = null;
        for (let n = 1; n < kept.length; n++) {
          const on = inFocus(kept[n - 1]) && inFocus(kept[n]);
          if (!run || run.on !== on) {
            if (run) draw(run.indices, run.on ? lit : dimmed);
            run = { on, indices: [kept[n - 1]] };
          }
          run.indices.push(kept[n]);
        }
        if (run) draw(run.indices, run.on ? lit : dimmed);
      }

      // Where the track stops for a while, say so. The radius grows with the
      // logarithm of the stay, so twenty minutes and nine hours are legibly
      // different without the latter swallowing the map.
      for (let i = 0; i < track.segments.length; i++) {
        const [, end] = track.segments[i];
        const next = track.segments[i + 1];
        if (!next) continue;
        const held = track.points[next[0]][2] - track.points[end][2];
        const [x, y] = screen[end];
        overlay.append(svg('circle', { class: 'trace-dwell', cx: x, cy: y, r: clamp(5 + Math.log2(held / 60) * 1.9, 6, 20) }));
      }

      const first = screen[0];
      const last = screen[screen.length - 1];
      overlay.append(svg('circle', { class: 'trace-start', cx: first[0], cy: first[1], r: 6 }));
      overlay.append(svg('circle', { class: 'trace-end', cx: last[0], cy: last[1], r: 6 }));

      if (cursor) {
        const [x, y] = project(cursor[0], cursor[1], state.zoom);
        const accuracy = cursor[3] ? cursor[3] / metresPerPixel(cursor[1], state.zoom) : 0;
        if (accuracy > 4) overlay.append(svg('circle', { class: 'trace-accuracy', cx: x - originX, cy: y - originY, r: Math.min(accuracy, 400) }));
        overlay.append(svg('circle', { class: 'trace-cursor', cx: x - originX, cy: y - originY, r: 7 }));
      }
    }

    function drawScale(width) {
      const perPixel = metresPerPixel(state.lat, state.zoom);
      const target = Math.min(150, Math.max(70, width * 0.2));
      const raw = perPixel * target;
      const magnitude = 10 ** Math.floor(Math.log10(raw));
      const nice = [1, 2, 5, 10].map((m) => m * magnitude).find((m) => m >= raw) ?? magnitude * 10;
      scaleBar.style.width = `${nice / perPixel}px`;
      scaleBar.textContent = nice >= 1000 ? `${nice / 1000} km` : `${nice} m`;
    }

    // ---- render ---------------------------------------------------------

    let frame = 0;
    function render() {
      frame = 0;
      if (destroyed) return;
      const width = container.clientWidth;
      const height = container.clientHeight;
      // Zero while the tab is hidden. The ResizeObserver below brings us back.
      if (!width || !height) return;
      const [cx, cy] = project(state.lng, state.lat, state.zoom);
      const originX = cx - width / 2;
      const originY = cy - height / 2;
      drawTiles(width, height, originX, originY);
      drawOverlay(width, height, originX, originY);
      drawScale(width);
    }

    function schedule() {
      if (!frame) frame = requestAnimationFrame(render);
    }

    const observer = new ResizeObserver(schedule);
    observer.observe(container);

    // ---- interaction ----------------------------------------------------

    function panByPixels(dx, dy) {
      const [cx, cy] = project(state.lng, state.lat, state.zoom);
      [state.lng, state.lat] = unproject(cx - dx, cy - dy, state.zoom);
      schedule();
    }

    function zoomAround(clientX, clientY, nextZoom) {
      const rect = container.getBoundingClientRect();
      const px = clientX - rect.left - rect.width / 2;
      const py = clientY - rect.top - rect.height / 2;
      const [cx, cy] = project(state.lng, state.lat, state.zoom);
      const [anchorLng, anchorLat] = unproject(cx + px, cy + py, state.zoom);
      const clamped = clamp(nextZoom, MIN_ZOOM, MAX_ZOOM);
      if (clamped !== state.zoom) lastZoomChange = performance.now();
      state.zoom = clamped;
      const [ax, ay] = project(anchorLng, anchorLat, state.zoom);
      [state.lng, state.lat] = unproject(ax - px, ay - py, state.zoom);
      schedule();
    }

    function enableZoom() {
      if (zoomEnabled) return;
      zoomEnabled = true;
      hint.hidden = true;
    }

    container.addEventListener('pointerdown', (event) => {
      enableZoom();
      container.focus({ preventScroll: true });
      container.setPointerCapture(event.pointerId);
      pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
      if (pointers.size === 2) {
        const [a, b] = [...pointers.values()];
        pinch = { distance: Math.hypot(a.x - b.x, a.y - b.y), zoom: state.zoom };
      }
    });

    container.addEventListener('pointermove', (event) => {
      const previous = pointers.get(event.pointerId);
      if (!previous) return;
      const dx = event.clientX - previous.x;
      const dy = event.clientY - previous.y;
      pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
      if (pointers.size === 2 && pinch) {
        const [a, b] = [...pointers.values()];
        const distance = Math.hypot(a.x - b.x, a.y - b.y);
        if (distance > 0 && pinch.distance > 0) {
          zoomAround((a.x + b.x) / 2, (a.y + b.y) / 2, pinch.zoom + Math.log2(distance / pinch.distance));
        }
        return;
      }
      panByPixels(dx, dy);
    });

    for (const type of ['pointerup', 'pointercancel']) {
      container.addEventListener(type, (event) => {
        pointers.delete(event.pointerId);
        if (pointers.size < 2) pinch = null;
        if (container.hasPointerCapture?.(event.pointerId)) container.releasePointerCapture(event.pointerId);
      });
    }

    container.addEventListener(
      'wheel',
      (event) => {
        // The page scrolls normally until the map has been clicked. Copied from
        // the site's own track map: a map that swallows the scroll wheel on the
        // way past is the single most complained-about thing a map can do.
        if (!zoomEnabled) return;
        event.preventDefault();
        const lines = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? 400 : 1;
        zoomAround(event.clientX, event.clientY, state.zoom - (event.deltaY * lines) / 420);
      },
      { passive: false },
    );

    container.addEventListener('focus', enableZoom);
    container.addEventListener('blur', () => { zoomEnabled = false; hint.hidden = false; });

    container.addEventListener('keydown', (event) => {
      const step = event.shiftKey ? 200 : 60;
      const moves = { ArrowLeft: [step, 0], ArrowRight: [-step, 0], ArrowUp: [0, step], ArrowDown: [0, -step] };
      if (moves[event.key]) { event.preventDefault(); panByPixels(...moves[event.key]); return; }
      if (event.key === '+' || event.key === '=') { event.preventDefault(); zoomAround(...centreOfContainer(), state.zoom + 1); }
      if (event.key === '-' || event.key === '_') { event.preventDefault(); zoomAround(...centreOfContainer(), state.zoom - 1); }
    });

    function centreOfContainer() {
      const rect = container.getBoundingClientRect();
      return [rect.left + rect.width / 2, rect.top + rect.height / 2];
    }

    // ---- public surface -------------------------------------------------

    return {
      /**
       * Ask the main site for its public Mapbox token and switch imagery on.
       *
       * Best effort by design: the endpoint belongs to a different process, and
       * a companion dashboard that cannot draw its own map because the site is
       * mid-deploy is worse than one drawing a track on a plain ground.
       */
      async useImagery() {
        try {
          const response = await fetch('/api/maps/config');
          if (!response.ok) return false;
          const config = await response.json();
          template = rasterTemplate(config.style, config.accessToken);
          setAttribution(Boolean(template));
          schedule();
          return Boolean(template);
        } catch {
          return false;
        }
      },
      /**
       * @param points  tuples of [lng, lat, epochSeconds, accuracyMetres, moving, speed]
       * @param segments inclusive [first, last] index pairs of continuous recording
       * @param colours  optional per-point stroke colours, indexed alongside `points`
       * @param focus    optional inclusive [first, last] range to light up, the
       *                 rest of the day drawn dimmed behind it
       */
      setTrack({ points = [], segments = [], colours = null, focus = null }) {
        track = { points, segments, colours, focus };
        schedule();
      },
      setCursor(point) {
        cursor = point;
        schedule();
        onCursorChange?.(point);
      },
      /** Frame every point, with a little air, without ever zooming past MAX_ZOOM. */
      fitPoints(points, padding = 48) {
        if (!points.length) return;
        const lngs = points.map((p) => p[0]);
        const lats = points.map((p) => p[1]);
        const west = Math.min(...lngs), east = Math.max(...lngs);
        const south = Math.min(...lats), north = Math.max(...lats);
        state.lng = (west + east) / 2;
        state.lat = (south + north) / 2;
        const width = Math.max(1, container.clientWidth - padding * 2);
        const height = Math.max(1, container.clientHeight - padding * 2);
        let best = MIN_ZOOM;
        for (let zoom = MAX_ZOOM; zoom >= MIN_ZOOM; zoom -= 0.25) {
          const [x1, y1] = project(west, north, zoom);
          const [x2, y2] = project(east, south, zoom);
          if (Math.abs(x2 - x1) <= width && Math.abs(y2 - y1) <= height) { best = zoom; break; }
        }
        // A single fix has no extent; framing it exactly would mean zoom 18 on
        // a point with ±30 m of error, which reads as precision that is not there.
        state.zoom = west === east && south === north ? 15 : clamp(best, MIN_ZOOM, MAX_ZOOM);
        lastZoomChange = performance.now();
        schedule();
      },
      refresh: schedule,
      destroy() {
        destroyed = true;
        observer.disconnect();
        if (frame) cancelAnimationFrame(frame);
      },
    };
  }

  window.SRMap = { create, project, unproject, metresPerPixel };
})();
