/**
 * The Movement tab: a day's track on a map, with that day's health under it.
 *
 * Two calls back the whole view — `/api/apple/track` for the geometry and the
 * day index, `/api/apple/timeline` for the health laid against it — and the
 * timeline owns the cursor, because hovering a heart rate and seeing where you
 * were is the thing this page is for.
 *
 * ## The day boundary is the BROWSER's
 *
 * Everything is stored in UTC and bucketed into local days using the offset
 * this browser reports, because a walk that starts at half past midnight in
 * summer otherwise appears on the day before. See `server/movement.mjs` for
 * what that costs on the two days a year the clocks move.
 */
(function () {
  const $ = (id) => document.getElementById(id);
  const svgNS = 'http://www.w3.org/2000/svg';
  const el = (name, attributes = {}, text = null) => {
    const node = document.createElementNS(svgNS, name);
    for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, value);
    if (text !== null) node.textContent = text;
    return node;
  };
  const node = (tag, text, className) => {
    const n = document.createElement(tag);
    if (text != null) n.textContent = text;
    if (className) n.className = className;
    return n;
  };
  const clamp = (value, lo, hi) => Math.min(hi, Math.max(lo, value));

  /**
   * One sequential ramp, light to dark, for every colour mode.
   *
   * Sequential and single-hue on purpose: speed, heart rate and time of day are
   * all magnitudes, and a multi-hue rainbow would imply categories none of them
   * has. It also keeps the trace legible to a reader who cannot separate the
   * site's orange from its petrol green — the ordering is carried by lightness,
   * which survives any colour vision.
   */
  const RAMP = ['#efc48d', '#d9861f', '#b35408', '#8a3b05', '#4d1f03'];
  const hex = (value) => [1, 3, 5].map((i) => parseInt(value.slice(i, i + 2), 16));
  const channels = RAMP.map(hex);
  function rampColour(t) {
    const position = clamp(t, 0, 1) * (channels.length - 1);
    const low = Math.floor(position);
    const high = Math.min(channels.length - 1, low + 1);
    const mix = position - low;
    const parts = channels[low].map((c, i) => Math.round(c + (channels[high][i] - c) * mix));
    return `#${parts.map((c) => c.toString(16).padStart(2, '0')).join('')}`;
  }

  const kilometres = (metres) => (metres >= 1000 ? `${(metres / 1000).toFixed(metres >= 10000 ? 0 : 1)} km` : `${Math.round(metres)} m`);
  function duration(seconds) {
    const total = Math.round(seconds / 60);
    return total >= 60 ? `${Math.floor(total / 60)}h ${String(total % 60).padStart(2, '0')}m` : `${total}m`;
  }
  const clock = (epochSeconds) => new Date(epochSeconds * 1000).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  const dayName = (date) => new Date(`${date}T12:00:00`).toLocaleDateString([], { weekday: 'short', day: 'numeric', month: 'short' });
  const median = (values) => (values.length ? [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)] : null);

  /**
   * Total time covered by a set of spans, clipped to a window and counted ONCE.
   *
   * A union rather than a sum because sleep stages overlap across sources — the
   * health tab says as much in its own words — so adding a watch's `deep` to a
   * phone's `asleep` reports a night longer than the night was. Clipped because
   * a stage is selected when it overlaps the day, and the part of it that fell
   * on the day before belongs to the day before.
   */
  function unionSeconds(spans, from, to) {
    let total = 0;
    let covered = from;
    for (const [start, end] of [...spans].sort((a, b) => a[0] - b[0])) {
      const open = Math.max(start, from, covered);
      const close = Math.min(end, to);
      if (close > open) { total += close - open; covered = close; }
    }
    return total;
  }

  async function api(path) {
    const response = await fetch(`/api/apple/${path}`);
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || 'Request failed');
    return result;
  }

  const state = {
    offset: new Date().getTimezoneOffset(),
    days: [],
    date: null,
    day: null,
    timeline: null,
    colourBy: 'time',
    focus: null,
    loaded: false,
  };
  let map = null;
  let timelineObserver = null;

  function fail(message) {
    $('error').textContent = message;
    $('error').hidden = !message;
  }

  // ---- the day strip ----------------------------------------------------

  function drawDays() {
    const strip = $('movement-days');
    strip.replaceChildren();
    for (const day of state.days) {
      const button = node('button', null, 'day');
      button.type = 'button';
      button.setAttribute('aria-pressed', String(day.date === state.date));
      button.append(node('small', dayName(day.date)), node('strong', kilometres(day.metres)), node('small', `${day.journeys ?? 0} ${day.journeys === 1 ? 'journey' : 'journeys'}`, 'muted'));
      button.onclick = () => selectDay(day.date);
      strip.append(button);
    }
  }

  // ---- colour modes -----------------------------------------------------

  /**
   * Heart rate at a moment, from the binned series.
   *
   * Returns null rather than the nearest reading when the nearest reading is
   * more than one bin away: the watch comes off, and a colour carried across a
   * two-hour hole would state a heart rate nobody measured.
   */
  function heartRateAt(epochSeconds) {
    const series = state.timeline?.heartRate;
    if (!series?.bins.length) return null;
    let best = null;
    let bestGap = Infinity;
    for (const [at, value] of series.bins) {
      const gap = Math.abs(at + series.seconds / 2 - epochSeconds);
      if (gap < bestGap) { bestGap = gap; best = value; }
    }
    return bestGap <= series.seconds ? best : null;
  }

  /** Per-point colours plus the legend's two end labels, for the current mode. */
  function colourTrack() {
    const points = state.day?.points ?? [];
    if (!points.length) return { colours: null, legend: null };
    if (state.colourBy === 'time') {
      const from = state.day.from;
      const span = state.day.to - state.day.from;
      return {
        colours: points.map((p) => rampColour((p[2] - from) / span)),
        legend: { low: '00:00', high: '24:00', label: 'Time of day' },
      };
    }
    const values = points.map((p) => (state.colourBy === 'speed' ? p[5] * 3.6 : heartRateAt(p[2])));
    const usable = values.filter((v) => v != null && v > 0).sort((a, b) => a - b);
    if (usable.length < 2) return { colours: null, legend: null };
    // Percentile bounds, so one GPS jump or one 180 bpm spike does not flatten
    // the whole ramp into a single shade.
    const low = usable[Math.floor(usable.length * 0.05)];
    const high = usable[Math.floor(usable.length * 0.95)];
    const span = high - low || 1;
    const unit = state.colourBy === 'speed' ? 'km/h' : 'bpm';
    return {
      colours: values.map((v) => (v == null ? '#9a8d7c' : rampColour((v - low) / span))),
      legend: {
        low: `${Math.round(low)} ${unit}`,
        high: `${Math.round(high)} ${unit}`,
        label: state.colourBy === 'speed' ? 'Speed' : 'Heart rate',
        muted: values.some((v) => v == null) ? 'grey where no reading' : null,
      },
    };
  }

  function drawLegend(legend) {
    const target = $('movement-legend');
    target.replaceChildren();
    if (!legend) return;
    target.append(node('span', legend.low, 'legend-end'));
    const swatches = node('span', null, 'legend-ramp');
    for (let i = 0; i < 24; i++) {
      const cell = node('i');
      cell.style.background = rampColour(i / 23);
      swatches.append(cell);
    }
    target.append(swatches, node('span', legend.high, 'legend-end'));
    if (legend.muted) target.append(node('span', legend.muted, 'muted'));
  }

  // ---- activities -------------------------------------------------------

  /**
   * The Watch's own name for a journey, if it recorded one over the same time.
   *
   * Worth joining because the two know different things: the track knows where
   * the phone was, the Watch knows it was a walk and measured the distance on
   * the wrist. They disagree on distance by a few hundred metres — GPS noise
   * between fixes inflates the track — so both are shown and each is labelled.
   */
  function workoutFor(activity) {
    let best = null;
    let bestOverlap = 0;
    for (const workout of state.timeline?.workouts ?? []) {
      const overlap = Math.min(Date.parse(workout.end) / 1000, activity.to) - Math.max(Date.parse(workout.start) / 1000, activity.from);
      if (overlap > bestOverlap) { bestOverlap = overlap; best = workout; }
    }
    // Enough overlap to be the same outing rather than one that brushed past it.
    return bestOverlap >= Math.min(120, activity.seconds / 2) ? best : null;
  }

  /** Mean heart rate over a window, from the binned series, or null. */
  function heartRateOver(from, to) {
    const bins = (state.timeline?.heartRate?.bins ?? []).filter(([at]) => at >= from && at < to);
    return bins.length ? Math.round(bins.reduce((sum, [, value]) => sum + value, 0) / bins.length) : null;
  }

  function drawActivities() {
    const target = $('movement-activities');
    target.replaceChildren();
    const activities = state.day?.activities ?? [];
    if (!activities.length) {
      target.append(node('p', 'No movement recorded on this day.', 'muted'));
      return;
    }
    activities.forEach((activity, index) => {
      const row = node('button', null, 'activity');
      row.type = 'button';
      row.setAttribute('aria-pressed', String(state.focus === index));
      const when = node('div', null, 'activity-when');
      when.append(node('strong', `${clock(activity.from)} – ${clock(activity.to)}`), node('small', duration(activity.seconds), 'muted'));
      const what = node('div', null, 'activity-what');
      const facts = node('div', null, 'activity-facts');
      if (activity.kind === 'journey') {
        const workout = workoutFor(activity);
        what.append(node('strong', workout ? workout.activity : 'Journey'));
        const bpm = heartRateOver(activity.from, activity.to);
        facts.append(node('strong', kilometres(activity.metres)));
        const detail = [`${((activity.metres / activity.seconds) * 3.6).toFixed(1)} km/h`];
        if (bpm) detail.push(`${bpm} bpm`);
        facts.append(node('small', detail.join(' · '), 'muted'));
        if (workout?.distance) what.append(node('small', `Watch measured ${kilometres(workout.distance)}`, 'muted'));
        else what.append(node('small', `${activity.fixes} fixes`, 'muted'));
      } else {
        what.append(node('strong', 'Stopped'), node('small', `${activity.fixes} ${activity.fixes === 1 ? 'fix' : 'fixes'} while here`, 'muted'));
        facts.append(node('strong', '—'), node('small', 'not moving', 'muted'));
      }
      row.append(when, what, facts);
      row.onclick = () => focusActivity(state.focus === index ? null : index);
      target.append(row);
    });
  }

  /** Light one activity on the map and dim the rest of the day behind it. */
  function focusActivity(index, { refit = true } = {}) {
    state.focus = index;
    const activity = index == null ? null : state.day.activities[index];
    const { colours } = colourTrack();
    map.setTrack({
      points: state.day.points,
      segments: state.day.segments,
      colours,
      focus: activity ? [activity.first, activity.last] : null,
    });
    if (refit) map.fitPoints(activity ? state.day.points.slice(activity.first, activity.last + 1) : state.day.points);
    drawActivities();
    drawTimeline();
  }

  // ---- the timeline -----------------------------------------------------

  const SLEEP_SHADE = { awake: 0.12, in_bed: 0.18, core: 0.34, rem: 0.46, deep: 0.62, asleep: 0.4 };

  function drawTimeline() {
    const host = $('movement-timeline');
    const width = host.clientWidth;
    host.replaceChildren();
    if (!width || !state.day) return;
    const height = 176;
    const padLeft = 34;
    const padRight = 8;
    const plot = Math.max(10, width - padLeft - padRight);
    const { from, to } = state.day;
    const x = (epochSeconds) => padLeft + ((epochSeconds - from) / (to - from)) * plot;

    const chart = el('svg', { class: 'timeline', width, height, viewBox: `0 0 ${width} ${height}`, role: 'img' });
    chart.setAttribute('aria-label', `Heart rate, workouts, sleep and recording for ${dayName(state.date)}`);
    // Published so the verification script can point at a time of day rather
    // than guess a fraction of the element's width and land in the axis gutter.
    chart.dataset.plotLeft = padLeft;
    chart.dataset.plotWidth = plot;

    const hrTop = 14;
    const hrHeight = 88;
    const workoutTop = hrTop + hrHeight + 10;
    const recordTop = workoutTop + 16;

    // Sleep sits behind everything, because it is the only thing on this chart
    // that is a condition rather than an event.
    for (const block of state.timeline?.sleep ?? []) {
      const start = clamp(Date.parse(block.start) / 1000, from, to);
      const end = clamp(Date.parse(block.end) / 1000, from, to);
      if (end <= start) continue;
      chart.append(el('rect', {
        x: x(start), y: hrTop, width: Math.max(1, x(end) - x(start)), height: hrHeight,
        fill: '#0e5b66', opacity: SLEEP_SHADE[block.stage] ?? 0.25,
      }));
    }

    // Hour grid and labels.
    const tickHours = width < 520 ? 6 : 3;
    for (let hour = 0; hour <= 24; hour += tickHours) {
      const at = from + hour * 3600;
      chart.append(el('line', { x1: x(at), y1: hrTop, x2: x(at), y2: recordTop + 12, class: 'grid' }));
      if (hour < 24) chart.append(el('text', { x: x(at) + 3, y: height - 4, class: 'axis' }, clock(at)));
    }

    // Heart rate.
    const series = state.timeline?.heartRate;
    if (series?.bins.length) {
      const values = series.bins.map(([, value]) => value);
      const low = Math.min(...values);
      const high = Math.max(...values);
      const span = Math.max(1, high - low);
      const y = (value) => hrTop + hrHeight - ((value - low) / span) * (hrHeight - 8) - 4;
      let path = '';
      let previous = null;
      for (const [at, value] of series.bins) {
        // A bin more than two bins from the last one is a hole, not a slope.
        const broken = previous === null || at - previous > series.seconds * 2.5;
        path += `${broken ? 'M' : 'L'}${x(at + series.seconds / 2).toFixed(1)} ${y(value).toFixed(1)}`;
        previous = at;
      }
      chart.append(el('path', { d: path, class: 'hr-line' }));
      for (const [value, label] of [[high, `${high}`], [low, `${low}`]]) {
        chart.append(el('text', { x: 2, y: y(value) + 4, class: 'axis' }, label));
      }
      chart.append(el('text', { x: 2, y: hrTop - 4, class: 'axis' }, 'bpm'));
    } else {
      chart.append(el('text', { x: padLeft, y: hrTop + hrHeight / 2, class: 'axis' }, 'No heart rate recorded for this day'));
    }

    // Workouts.
    for (const workout of state.timeline?.workouts ?? []) {
      const start = clamp(Date.parse(workout.start) / 1000, from, to);
      const end = clamp(Date.parse(workout.end) / 1000, from, to);
      if (end <= start) continue;
      chart.append(el('rect', { x: x(start), y: workoutTop, width: Math.max(2, x(end) - x(start)), height: 10, class: 'workout' }));
      chart.append(el('title', {}, `${workout.activity} · ${duration(workout.seconds)} from ${clock(start)}`));
    }

    // The day as journeys and stops, on the same axis as everything above.
    // Bare ground at either end is time with no fix at all.
    chart.append(el('rect', { x: padLeft, y: recordTop, width: plot, height: 8, class: 'record-off' }));
    (state.day.activities ?? []).forEach((activity, index) => {
      chart.append(el('rect', {
        x: x(activity.from), y: recordTop, width: Math.max(2, x(activity.to) - x(activity.from)), height: 8,
        class: `${activity.kind === 'journey' ? 'record-journey' : 'record-stop'}${state.focus === index ? ' record-focused' : ''}`,
      }));
    });

    const marker = el('line', { x1: 0, y1: hrTop, x2: 0, y2: recordTop + 8, class: 'timeline-cursor' });
    marker.style.display = 'none';
    chart.append(marker);

    const moveTo = (clientX) => {
      const rect = chart.getBoundingClientRect();
      const ratio = clamp((clientX - rect.left - padLeft) / plot, 0, 1);
      const at = from + ratio * (to - from);
      marker.setAttribute('x1', x(at));
      marker.setAttribute('x2', x(at));
      marker.style.display = '';
      showMoment(at);
    };
    chart.addEventListener('pointermove', (event) => moveTo(event.clientX));
    chart.addEventListener('pointerdown', (event) => moveTo(event.clientX));
    chart.addEventListener('pointerleave', () => {
      marker.style.display = 'none';
      map?.setCursor(null);
      $('movement-readout').textContent = defaultReadout();
    });
    host.append(chart);

    // Without this the sleep band, the workout blocks and the recording strip
    // are three colours the reader has to guess at.
    const key = node('p', null, 'timeline-key');
    for (const [label, className] of [['Asleep', 'key-sleep'], ['Heart rate', 'key-hr'], ['Workout', 'key-workout'], ['Journey', 'key-journey'], ['Stopped', 'key-stop']]) {
      const item = node('span', null, 'key-item');
      item.append(node('i', null, className), node('span', label));
      key.append(item);
    }
    host.append(key);
  }

  function defaultReadout() {
    if (!state.day?.points.length) return '';
    const first = state.day.points[0][2];
    const last = state.day.points[state.day.points.length - 1][2];
    return `Recorded ${clock(first)} to ${clock(last)}. Move along the chart to follow the day.`;
  }

  /**
   * Put the map's dot where the reader is pointing on the timeline.
   *
   * A fix further away in time than the segment gap is NOT shown as a position:
   * the phone was asleep, and drawing a dot there would claim to know something
   * the recording does not.
   */
  function showMoment(epochSeconds) {
    const points = state.day?.points ?? [];
    let nearest = null;
    let gap = Infinity;
    for (const point of points) {
      const distance = Math.abs(point[2] - epochSeconds);
      if (distance < gap) { gap = distance; nearest = point; }
    }
    const parts = [clock(epochSeconds)];
    const bpm = heartRateAt(epochSeconds);
    if (bpm) parts.push(`${bpm} bpm`);
    if (nearest && gap <= (state.day.gapSeconds ?? 600)) {
      map?.setCursor(nearest);
      parts.push(`${(nearest[5] * 3.6).toFixed(1)} km/h`, nearest[4] ? 'moving' : 'still', `±${Math.round(nearest[3])} m`);
      if (gap > 60) parts.push(`nearest fix ${duration(gap)} away`);
    } else {
      map?.setCursor(null);
      parts.push(nearest ? 'no fix — the phone was asleep' : 'no location recorded');
    }
    $('movement-readout').textContent = parts.join(' · ');
  }

  // ---- stats ------------------------------------------------------------

  function drawStats() {
    const target = $('movement-stats');
    target.replaceChildren();
    const totals = state.day?.totals ?? { metres: 0, movingSeconds: 0, fixes: 0 };
    const accuracy = median((state.day?.points ?? []).map((p) => p[3]));
    const sleep = unionSeconds(
      (state.timeline?.sleep ?? [])
        .filter((s) => ['asleep', 'core', 'deep', 'rem'].includes(s.stage))
        .map((s) => [Date.parse(s.start) / 1000, Date.parse(s.end) / 1000]),
      state.day.from,
      state.day.to,
    );
    // The phone uploads ONE cumulative-sum row per calendar day, so the right
    // answer for a day is that row — never the sum of every row the window
    // touches, which would add two days together at a boundary.
    const steps = (state.timeline?.steps ?? [])
      .map((record) => ({ ...record, overlap: Math.min(Date.parse(record.end) / 1000, state.day.to) - Math.max(Date.parse(record.start) / 1000, state.day.from) }))
      .sort((a, b) => b.overlap - a.overlap)[0];
    const tiles = [
      ['RECORDED MOVEMENT', kilometres(totals.metres), 'Along recorded fixes only'],
      ['MOVING', duration(totals.movingSeconds), `${totals.fixes} fixes${accuracy ? ` · ±${Math.round(accuracy)} m typical` : ''}`],
      ['STEPS', steps ? steps.value.toLocaleString() : '—', steps ? 'HealthKit daily total' : 'No daily total uploaded'],
      ['ASLEEP', sleep ? duration(sleep) : '—', sleep ? 'Inside this day, across sources' : 'No sleep recorded'],
      ['RESTING HEART RATE', state.timeline?.restingHeartRate ? `${state.timeline.restingHeartRate.value} bpm` : '—', state.timeline?.restingHeartRate ? `Latest to ${clock(Date.parse(state.timeline.restingHeartRate.at) / 1000)}` : 'No reading'],
      ['JOURNEYS', String(totals.journeys ?? 0), `${(state.day?.activities ?? []).filter((a) => a.kind === 'stop').length} stops between them`],
    ];
    for (const [label, value, note] of tiles) {
      const tile = node('div', null, 'metric');
      tile.append(node('small', label), node('strong', value), node('small', note, 'when'));
      target.append(tile);
    }
  }

  // ---- loading ----------------------------------------------------------

  function paintDay() {
    const { colours, legend } = colourTrack();
    drawLegend(legend);
    map.setTrack({ points: state.day.points, segments: state.day.segments, colours, focus: null });
    map.fitPoints(state.day.points);
    drawStats();
    drawActivities();
    drawTimeline();
    $('movement-readout').textContent = defaultReadout();
    const notes = [];
    if (state.day.truncated) notes.push(`Only the most recent fixes are shown — this account has more than the ${state.day.retentionDays}-day view can carry.`);
    notes.push(`Location history is kept for ${state.day.retentionDays} days and then deleted.`);
    $('movement-notes').textContent = notes.join(' ');
  }

  async function selectDay(date) {
    try {
      state.date = date;
      state.focus = null;
      drawDays();
      const day = await api(`track?offset=${state.offset}&date=${date}`);
      state.days = day.days;
      state.day = day;
      state.timeline = await api(`timeline?from=${day.from}&to=${day.to}`).catch(() => null);
      drawDays();
      paintDay();
    } catch (error) {
      fail(error.message);
    }
  }

  function showEmpty(message) {
    $('movement-body').hidden = true;
    $('movement-empty').hidden = false;
    $('movement-empty').replaceChildren(node('p', message));
  }

  async function open() {
    if (state.loaded) {
      map?.refresh();
      drawTimeline();
      return;
    }
    const index = await api(`track?offset=${state.offset}`);
    state.days = index.days;
    state.loaded = true;
    if (!index.days.length) {
      showEmpty('No location has been recorded yet. Pair your iPhone, turn on location sharing under Connect & privacy, and the map fills in as the phone syncs.');
      return;
    }
    $('movement-empty').hidden = true;
    $('movement-body').hidden = false;
    if (!map) {
      map = window.SRMap.create($('movement-map'));
      // Best effort: the token belongs to the main site, and a companion that
      // cannot draw a basemap should still draw the track.
      await map.useImagery();
      timelineObserver = new ResizeObserver(() => drawTimeline());
      timelineObserver.observe($('movement-timeline'));
      $('movement-colour').onchange = () => {
        state.colourBy = $('movement-colour').value;
        if (state.day) { drawLegend(colourTrack().legend); focusActivity(state.focus, { refit: false }); }
      };
      $('movement-refresh').onclick = () => { state.loaded = false; open().catch((error) => fail(error.message)); };
    }
    await selectDay(state.date && index.days.some((d) => d.date === state.date) ? state.date : index.days[0].date);
  }

  /** Signing out must not leave one account's track on screen for the next. */
  function reset() {
    state.loaded = false;
    state.days = [];
    state.date = null;
    state.day = null;
    state.timeline = null;
    state.focus = null;
    map?.destroy();
    map = null;
    timelineObserver?.disconnect();
    timelineObserver = null;
    $('movement-map').replaceChildren();
    $('movement-map').className = '';
    $('movement-timeline').replaceChildren();
    $('movement-stats').replaceChildren();
    $('movement-days').replaceChildren();
    $('movement-activities').replaceChildren();
    $('movement-legend').replaceChildren();
    $('movement-readout').textContent = '';
  }

  window.SRMovement = { open, reset };
})();
