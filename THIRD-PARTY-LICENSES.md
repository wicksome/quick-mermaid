# Third-Party Licenses

QuickMermaid bundles the following third-party components (vendored under
`Resources/`). Their licenses and required notices are reproduced below. No
component is loaded from the network at runtime.

---

## Mermaid — `Resources/mermaid.min.js`

MIT License — Copyright (c) 2014–present Knut Sveidqvist
<https://github.com/mermaid-js/mermaid>

---

## PlantUML engine — `Resources/plantuml.js`

PlantUML is multi-licensed; per its README the recipient may choose one of
GPL / LGPL / Apache / Eclipse Public / MIT. **QuickMermaid uses PlantUML under
the MIT License.**

MIT License — Copyright (c) 2009–2025 Arnaud Roques
<https://github.com/plantuml/plantuml> (see the multi-license offer in its README)

`plantuml.js` is the upstream TeaVM build with one mechanical change (its ES
-module `export` is rewrapped as a global so it loads as a classic script in a
`file://` WebView); the PlantUML/Graphviz logic is unmodified.

## TeaVM runtime — emitted inside `Resources/plantuml.js`

Apache License 2.0 — Copyright Alexey Andreev and contributors
<https://github.com/konsoletyper/teavm> — full text: <https://www.apache.org/licenses/LICENSE-2.0>

---

## Viz.js — `Resources/viz-global.js`

MIT License — Copyright (c) Michael Daines
<https://github.com/mdaines/viz-js>

`viz-global.js` additionally contains, in compiled (object/WASM) form:

### Graphviz

Eclipse Public License — Copyright (c) AT&T and contributors.
<https://graphviz.org/license/> — source: <https://gitlab.com/graphviz/graphviz>
(bundled unmodified, in object-code form)

### Expat

MIT License — Copyright (c) 1998–2000 Thai Open Source Software Center Ltd and
Clark Cooper; Copyright (c) 2001–2025 Expat maintainers.
<https://github.com/libexpat/libexpat>

---

## MIT License (text)

The MIT-licensed components above are provided under the following terms:

```
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
