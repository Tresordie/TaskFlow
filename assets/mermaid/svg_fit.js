// Model-SVG text-overflow repair — JS port of the voice_transcription
// reference `richRender.ts` (sanitizeSvgString + fitSvgText family),
// type annotations stripped, DOMPurify replaced by the reference's own
// string-level sanitizer (foreignObject / namespaces survive).
// Runs inside the export renderer WebView (v1.15.2): model-written SVG
// covers/figures often carry <text> lines wider than their box/viewBox —
// clipped beyond recovery unless fixed here. Strategy (reference verbatim):
//   slight overflow (>=0.75x) -> shrink font-size;
//   much content (<0.75x)     -> wrap into lines, grow the containing rect
//                                and shift everything below out of the way;
//   styled tspan mixes        -> textLength compression fallback;
//   missing viewBox           -> derive from width/height attributes;
//   content taller than declared -> extend viewBox via getBBox.

/** String-level SVG sanitization: strip script vectors, keep all visuals. */
function sanitizeSvgString(svg) {
  return svg
    .replace(/<script[\s\S]*?<\/script\s*>/gi, '')
    .replace(/\son\w+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)/gi, '')
    .replace(
      /(href|xlink:href)\s*=\s*(?:"\s*javascript:[^"]*"|'\s*javascript:[^']*'|javascript:[^\s>]+)/gi,
      '$1="#"',
    );
}

/** Read a presentational attribute from the element or its ancestor chain
 *  (font-size etc. inherit; models often put them on a <g>). */
function svgInheritedAttr(el, name) {
  var cur = el;
  while (cur && cur.getAttribute) {
    var own = cur.getAttribute(name);
    if (own) return own;
    var st = cur.getAttribute('style');
    if (st) {
      var m = new RegExp('(?:^|;)\\s*' + name + '\\s*:\\s*([^;]+)', 'i').exec(st);
      if (m) return m[1].trim();
    }
    cur = cur.parentElement;
  }
  return null;
}

var fitCtx = null;

/** Canvas text measurement with the element's inherited font. */
function measureSvgText(text, el) {
  if (!fitCtx) fitCtx = document.createElement('canvas').getContext('2d');
  if (!fitCtx) return text.length * 16;
  var size = parseFloat(svgInheritedAttr(el, 'font-size') || '') || 16;
  var weight = svgInheritedAttr(el, 'font-weight') || 'normal';
  var style = svgInheritedAttr(el, 'font-style') || 'normal';
  var family = svgInheritedAttr(el, 'font-family') || 'sans-serif';
  fitCtx.font = (style + ' ' + weight + ' ' + size + 'px ' + family).replace(/\s+/g, ' ').trim();
  return fitCtx.measureText(text).width;
}

/** Own translate offset (rotate/scale/matrix/skew => coords unreliable). */
function ownTranslate(el) {
  var tr = el.getAttribute('transform') || '';
  if (/(rotate|scale|matrix|skew)/i.test(tr)) return { dx: 0, dy: 0, ok: false };
  var tm = /translate\(\s*(-?[\d.]+)[\s,]*(-?[\d.]*)\s*\)/i.exec(tr);
  return {
    dx: tm ? parseFloat(tm[1]) || 0 : 0,
    dy: tm ? parseFloat(tm[2] || '0') || 0 : 0,
    ok: true,
  };
}

/** Accumulated ancestor translate offsets up to (excluding) root. */
function accumulateTranslate(el, root) {
  var dx = 0, dy = 0;
  var cur = el.parentElement;
  while (cur && cur !== root) {
    var tr = (cur.getAttribute && cur.getAttribute('transform')) || '';
    if (/(rotate|scale|matrix|skew)/i.test(tr)) return { dx: 0, dy: 0, ok: false };
    var tm = /translate\(\s*(-?[\d.]+)[\s,]*(-?[\d.]*)\s*\)/i.exec(tr);
    if (tm) {
      dx += parseFloat(tm[1]) || 0;
      dy += parseFloat(tm[2] || '0') || 0;
    }
    cur = cur.parentElement;
  }
  return { dx: dx, dy: dy, ok: true };
}

/** Container boxes (rect/path/polygon) with transform-adjusted geometry.
 *  Requires the SVG to be attached to the render tree (getBBox). */
function collectSvgBoxes(svg) {
  var boxes = [];
  svg.querySelectorAll('rect, path, polygon').forEach(function (el) {
    var bb;
    try { bb = el.getBBox(); } catch (e) { return; }
    if (!(bb.width > 0) || !(bb.height > 0)) return;
    var own = ownTranslate(el);
    if (!own.ok) return;
    var acc = accumulateTranslate(el, svg);
    if (!acc.ok) return;
    boxes.push({ x: bb.x + own.dx + acc.dx, y: bb.y + own.dy + acc.dy, w: bb.width, h: bb.height, el: el });
  });
  return boxes;
}

/** Greedy line breaking: prefer breaks after whitespace/CJK chars; hard-cut
 *  unbreakable runs (URLs / version numbers). */
function breakText(text, measure, maxWidth) {
  var isCjk = function (ch) { return /[⺀-鿿　-〿＀-￯—…]/.test(ch); };
  var chars = Array.from(text.replace(/\s+/g, ' ').trim());
  var lines = [];
  var cur = '';
  var lastBreak = -1;
  for (var i = 0; i < chars.length; i++) {
    var ch = chars[i];
    if (cur && measure(cur + ch) > maxWidth) {
      if (lastBreak > 0) {
        lines.push(cur.slice(0, lastBreak).trimEnd());
        cur = cur.slice(lastBreak).replace(/^ /, '');
      } else {
        lines.push(cur);
        cur = '';
      }
      lastBreak = -1;
      if (cur && measure(cur + ch) > maxWidth) {
        lines.push(cur);
        cur = '';
      }
    }
    cur += ch;
    if (ch === ' ' || isCjk(ch)) lastBreak = cur.length;
  }
  if (cur.trim()) lines.push(cur.trimEnd());
  return lines.filter(function (l) { return l.length > 0; });
}

/** Shift every positionable element whose final top lies below thresholdY
 *  down by delta (single-column model covers: wrapped lines push the rest). */
function shiftBelowSvg(svg, thresholdY, delta, skip) {
  if (!(delta > 0)) return;
  svg.querySelectorAll('rect, text, tspan, image, line, circle, ellipse').forEach(function (el) {
    if (skip.has(el)) return;
    var yOwn = parseFloat(el.getAttribute('y') || el.getAttribute('cy') || '');
    var y1 = parseFloat(el.getAttribute('y1') || '');
    var y2 = parseFloat(el.getAttribute('y2') || '');
    var accDy = 0;
    var cur = el.parentElement;
    while (cur && cur !== svg) {
      var tm = /translate\(\s*(-?[\d.]+)[\s,]*(-?[\d.]*)\s*\)/i.exec((cur.getAttribute && cur.getAttribute('transform')) || '');
      if (tm) accDy += parseFloat(tm[2] || '0') || 0;
      cur = cur.parentElement;
    }
    var top;
    if (isFinite(yOwn)) top = yOwn + accDy;
    else if (isFinite(y1) && isFinite(y2)) top = Math.min(y1, y2) + accDy;
    else return; // shapes without y info (path…) do not participate
    if (top <= thresholdY) return;
    var tr = el.getAttribute('transform');
    if (tr && /translate/i.test(tr)) {
      el.setAttribute(
        'transform',
        tr.replace(
          /translate\(\s*(-?[\d.]+)([\s,]+)(-?[\d.]+)\s*\)/i,
          function (_m, tx, sep, ty) { return 'translate(' + tx + sep + ((parseFloat(ty) || 0) + delta) + ')'; },
        ),
      );
    } else {
      el.setAttribute('transform', 'translate(0, ' + delta + ')' + (tr ? ' ' + tr : ''));
    }
  });
}

/** Wrap one overlong line into the available width: first line stays in the
 *  original element, further lines clone <text> below; containing rects grow
 *  and everything below shifts down so all wrapped text stays visible. */
function wrapSvgLine(el, avail, size, fy, startX, boxes) {
  var lines = breakText(el.textContent || '', function (s) { return measureSvgText(s, el); }, avail);
  if (lines.length <= 1) {
    el.setAttribute('textLength', String(Math.max(20, Math.round(avail))));
    el.setAttribute('lengthAdjust', 'spacingAndGlyphs');
    return;
  }
  var lineH = Math.round(size * 1.5);
  var delta = (lines.length - 1) * lineH;
  var y0 = parseFloat(el.getAttribute('y') || '0');
  var skip = new Set([el]);
  var prev = el;
  for (var i = 1; i < lines.length; i++) {
    var clone = el.cloneNode(false);
    clone.setAttribute('y', String(y0 + i * lineH));
    clone.textContent = lines[i];
    prev.parentNode.insertBefore(clone, prev.nextSibling);
    prev = clone;
    skip.add(clone);
  }
  el.textContent = lines[0];
  var neededBottom = fy + delta + Math.max(6, size * 0.4);
  for (var j = 0; j < boxes.length; j++) {
    var b = boxes[j];
    if (b.el.tagName !== 'rect') continue; // path boxes cannot grow height-only
    if (b.x - 2 <= startX && startX <= b.x + b.w && b.y <= fy && fy <= b.y + b.h) {
      if (neededBottom > b.y + b.h) {
        b.el.setAttribute('height', String(Math.round(b.h + (neededBottom - (b.y + b.h)))));
        b.h = neededBottom;
        skip.add(b.el);
      }
    }
  }
  shiftBelowSvg(el.ownerSVGElement || el, fy + lineH * 0.6, delta, skip);
}

/** Single-line overflow repair. Available width = min(smallest containing
 *  box, viewBox right edge); slight overflow shrinks the font, heavy content
 *  wraps, styled tspan mixes fall back to textLength compression. */
function fitSvgLine(el, W, boxes) {
  if (el.closest('foreignObject')) return;
  var content = (el.textContent || '').trim();
  if (!content) return;
  var xAttr = (el.getAttribute('x') || '').trim();
  if (!xAttr || /\s/.test(xAttr)) return;
  var x = parseFloat(xAttr);
  if (!isFinite(x) || x < 0) return;
  var y = parseFloat(el.getAttribute('y') || '');
  var hasY = isFinite(y);
  var own = ownTranslate(el);
  if (!own.ok) return;
  var svg = el.ownerSVGElement;
  var acc = svg ? accumulateTranslate(el, svg) : { dx: 0, dy: 0, ok: false };
  if (!acc.ok) return;
  var fx = x + own.dx + acc.dx;
  var fy = hasY ? y + own.dy + acc.dy : NaN;
  var anchor = (svgInheritedAttr(el, 'text-anchor') || 'start').trim();
  var m = measureSvgText(el.textContent || '', el);
  if (m <= 0) return;
  var startX = fx + (anchor === 'middle' ? -m / 2 : anchor === 'end' ? -m : 0);
  var size = parseFloat(svgInheritedAttr(el, 'font-size') || '') || 16;
  var box = null;
  if (isFinite(fy)) {
    for (var i = 0; i < boxes.length; i++) {
      var b = boxes[i];
      if (b.w < size || b.h < size * 0.8) continue; // rules / separators, not containers
      if (b.x - 2 <= startX && startX <= b.x + b.w && b.y <= fy && fy <= b.y + b.h) {
        if (!box || b.w < box.w) box = b;
      }
    }
  }
  var boxAvail = box ? box.x + box.w - 10 - startX : Infinity;
  var avail = Math.min(boxAvail, W - 10 - startX);
  if (avail <= 0 || m <= avail) return;
  var scale = avail / m;
  if (el.children.length === 0 && scale >= 0.75) {
    el.setAttribute('font-size', String(Math.round(size * scale * 10) / 10));
    return;
  }
  if (el.children.length === 0 && el.tagName === 'text' && hasY) {
    wrapSvgLine(el, avail, size, fy, startX, boxes);
    return;
  }
  el.setAttribute('textLength', String(Math.max(20, Math.round(avail))));
  el.setAttribute('lengthAdjust', 'spacingAndGlyphs');
}

/** Text-overflow repair + viewBox/height fallback for a model SVG string.
 *  Returns the repaired SVG string; non-SVG input passes through unchanged. */
function fitSvgText(svgText) {
  var trimmed = svgText.trim();
  if (!/^<svg[\s>]/i.test(trimmed)) return svgText;
  var holder = document.createElement('div');
  holder.innerHTML = sanitizeSvgString(trimmed);
  var svg = holder.querySelector('svg');
  if (!svg) return svgText;

  var wAttr = parseFloat(svg.getAttribute('width') || '');
  var hAttr = parseFloat(svg.getAttribute('height') || '');
  var vb = (svg.getAttribute('viewBox') || '').split(/[\s,]+/).map(Number);
  if (vb.length !== 4 || vb.some(function (n) { return !isFinite(n); })) vb = [];
  if (!vb.length && wAttr > 0 && hAttr > 0) {
    svg.setAttribute('viewBox', '0 0 ' + wAttr + ' ' + hAttr);
    vb = [0, 0, wAttr, hAttr];
  }
  var W = vb.length === 4 && vb[2] > 0 ? vb[2] : wAttr > 0 ? wAttr : 0;

  // Attach (hidden) to the render tree: path-box collection and content
  // height measurement both depend on getBBox.
  var needLayout = W > 0 || (vb.length === 4 && vb[3] > 0);
  if (needLayout) {
    holder.style.cssText = 'position:absolute;left:-9999px;top:0;visibility:hidden';
    document.body.appendChild(holder);
  }
  try {
    if (W > 0) {
      var boxes = collectSvgBoxes(svg);
      Array.from(svg.querySelectorAll('text')).forEach(function (t) {
        // Multi-line text (tspan with dy/y) cannot be measured as one line.
        if (Array.from(t.children).some(function (c) { return c.tagName === 'tspan' && (c.hasAttribute('dy') || c.hasAttribute('y')); })) return;
        var xTs = Array.from(t.querySelectorAll('tspan')).filter(function (s) {
          var xa = (s.getAttribute('x') || '').trim();
          return xa && !/\s/.test(xa);
        });
        if (xTs.length) xTs.forEach(function (s) { fitSvgLine(s, W, boxes); });
        else fitSvgLine(t, W, boxes);
      });
    }

    // Height fallback: extend the viewBox when content overflows the bottom.
    if (vb.length === 4 && vb[3] > 0) {
      var box = svg.getBBox();
      var contentH = box.y + box.height;
      if (contentH > vb[3] + 8) {
        var newH = Math.ceil(contentH + 8);
        svg.setAttribute('viewBox', vb[0] + ' ' + vb[1] + ' ' + (vb[2] || W) + ' ' + newH);
        if (svg.hasAttribute('height')) svg.setAttribute('height', String(newH));
      }
    }
  } catch (e) {
    //个别内容无法测量，忽略 (reference: swallow per-element measurement errors)
  } finally {
    if (needLayout) holder.remove();
  }
  return new XMLSerializer().serializeToString(svg);
}
