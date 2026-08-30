import { useMemo, useRef, useState } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import {
  ArrowRight, BookOpenText, Check, CheckSquare, ClipboardText, Code, FileText,
  FolderOpen, Hash, ListBullets, LockKey, MagnifyingGlass, Moon, NotePencil,
  PushPin, Quotes, ShieldCheck, SidebarSimple, Sparkle, Sun, Trash,
} from "@phosphor-icons/react";

const primaryNote = `# Field notes for better decisions

Good decisions rarely arrive as a flash. They emerge when the facts, tradeoffs, and next steps are visible in one quiet place.

## What we know

The strongest signal is **repeat behavior**, not a single enthusiastic comment. Keep the evidence close to the decision and separate observations from assumptions.

| Signal | What it tells us | Confidence |
| --- | --- | --- |
| Five repeat sessions | The workflow has durable value | High |
| Faster capture | The shortcut removes friction | High |
| One export request | Portability matters | Medium |

> Make the reversible choice quickly. Give the irreversible choice room to breathe.

## Before Friday

- [x] Gather the source notes
- [x] Name the decision owner
- [ ] Test the smallest reversible step
- [ ] Record what would change our mind

### Working rule

When the evidence is incomplete, write the assumption beside the action. Future-you deserves the context.

\`\`\`text
Decision = evidence + constraints + a clear next step
\`\`\`

---

_Captured locally in Clasp. Stored as portable Markdown._`;

const notes = [
  { id: "field-notes", title: "Field notes for better decisions", preview: "Good decisions rarely arrive as a flash. They emerge when the facts…", age: "4 min", pinned: true, tags: ["thinking", "today"], markdown: primaryNote },
  { id: "reading-list", title: "Reading list — August", preview: "Essays on attention, craft, and making software feel calm.", age: "28 min", tags: ["reading"], markdown: "# Reading list — August\n\n- The Shape of Design\n- The Humane Interface\n- A Pattern Language\n\n> Read slowly enough to disagree." },
  { id: "launch-checklist", title: "Launch checklist", preview: "A short, source-exact list for the final release pass.", age: "1 hr", tags: ["work", "today"], markdown: "# Launch checklist\n\n- [x] Review the welcome flow\n- [x] Verify keyboard shortcuts\n- [ ] Capture final screenshots\n- [ ] Archive the release notes" },
];

const vaultNote = {
  id: "wallet-research", title: "Wallet research — public references", preview: "Public addresses, device notes, and a recovery drill checklist.", age: "2 days", tags: ["research", "vault"],
  markdown: `# Wallet research — public references

## Cold-storage review

- [x] Label the public receiving addresses
- [ ] Rehearse the recovery process offline
- [ ] Confirm the hardware wallet firmware source

**Keep keys somewhere built for keys.** Clasp is useful for research, public-address labels, and recovery procedures—not seed phrases, private keys, recovery codes, or signing credentials.`,
};

const navItems = [["Inbox", ClipboardText], ["All Notes", FolderOpen], ["Pinned", PushPin], ["Vault", ShieldCheck], ["Trash", Trash]];

function BrandMark({ compact = false }) {
  return <img className={compact ? "brand-mark brand-mark--compact" : "brand-mark"} src="/clasp-app-icon.png" alt="" aria-hidden="true" />;
}

function Header() {
  return <header className="site-header shell">
    <a className="wordmark" href="#top" aria-label="Clasp home"><BrandMark compact /><span>Clasp</span></a>
    <nav aria-label="Primary navigation"><a href="#why">Why Clasp</a><a href="#safety">Safety</a><a href="#demo">Live demo</a><a href="#help">Help</a></nav>
    <a className="header-cta" href="#demo">Try the demo</a>
  </header>;
}

function Hero() {
  return <section className="hero shell" id="top">
    <div className="hero-copy">
      <p className="eyebrow"><Sparkle weight="fill" /> Private notes, without the performance</p>
      <h1>Catch it.<br />Keep it yours.</h1>
      <p className="hero-deck">A calm, local-first Markdown notebook for Mac. Capture quickly, read beautifully, and keep a portable source file underneath it all.</p>
      <div className="availability-card" aria-label="Mac App Store release status"><BrandMark compact /><div><strong>Clasp is preparing for the Mac App Store.</strong><span>We’re finishing the release with care for stability, privacy, and performance.</span></div></div>
      <div className="hero-actions"><a className="primary-action" href="#demo">Explore the live demo <ArrowRight /></a><a className="text-action" href="#safety">Read our safety approach</a></div>
    </div>
    <div className="hero-art"><img className="hero-screenshot" src="/clasp-demo.png" alt="Clasp showing a fully styled field note with headings, a table, checklist, quote, and code" /><img className="hero-icon" src="/clasp-app-icon.png" alt="Clasp Loop app icon" /></div>
  </section>;
}

function ModeButton({ active, children, onClick }) {
  return <button className={active ? "mode-button is-active" : "mode-button"} onClick={onClick}>{children}</button>;
}

function EditorToolbar({ mode, textareaRef, markdown, onChange }) {
  const apply = (before, after = before, block = false) => {
    const el = textareaRef.current;
    if (!el) return;
    const start = el.selectionStart;
    const end = el.selectionEnd;
    const selected = markdown.slice(start, end) || "selected text";
    const replacement = block ? selected.split("\n").map((line) => `${before}${line}`).join("\n") : `${before}${selected}${after}`;
    onChange(`${markdown.slice(0, start)}${replacement}${markdown.slice(end)}`);
    requestAnimationFrame(() => { el.focus(); el.setSelectionRange(start + before.length, start + replacement.length - after.length); });
  };
  return <div className="editor-toolbar" aria-label="Formatting toolbar">
    <button className="style-menu" onClick={() => mode === "markdown" && apply("## ", "", true)}><span>Aa</span> Style <span>⌄</span></button><i />
    <button aria-label="Bold" onClick={() => mode === "markdown" && apply("**")}><strong>B</strong></button>
    <button aria-label="Italic" onClick={() => mode === "markdown" && apply("_")}><em>I</em></button>
    <button aria-label="Inline code" onClick={() => mode === "markdown" && apply("`")}><Code /></button><i />
    <button aria-label="Bulleted list" onClick={() => mode === "markdown" && apply("- ", "", true)}><ListBullets /></button>
    <button aria-label="Checklist" onClick={() => mode === "markdown" && apply("- [ ] ", "", true)}><CheckSquare /></button>
    <button aria-label="Quote" onClick={() => mode === "markdown" && apply("> ", "", true)}><Quotes /></button>
    <span className="toolbar-hint">{mode === "page" ? "Edit the source in Markdown" : "Select text, then style"}</span>
  </div>;
}

function DemoApp({ capture = false }) {
  const [section, setSection] = useState("Inbox");
  const [selectedId, setSelectedId] = useState("field-notes");
  const [mode, setMode] = useState("page");
  const [query, setQuery] = useState("");
  const [vaultOpen, setVaultOpen] = useState(false);
  const [dark, setDark] = useState(false);
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [content, setContent] = useState(Object.fromEntries([...notes, vaultNote].map((note) => [note.id, note.markdown])));
  const textareaRef = useRef(null);
  const availableNotes = section === "Vault" ? (vaultOpen ? [vaultNote] : []) : notes.filter((note) => section !== "Pinned" || note.pinned).filter(() => section !== "Trash");
  const filtered = useMemo(() => availableNotes.filter((note) => `${note.title} ${note.preview} ${note.tags.join(" ")}`.toLowerCase().includes(query.toLowerCase())), [availableNotes, query]);
  const selected = [...notes, vaultNote].find((note) => note.id === selectedId) || filtered[0];
  const markdown = selected ? content[selected.id] : "";
  const changeMarkdown = (next) => selected && setContent((current) => ({ ...current, [selected.id]: next }));
  const selectSection = (name) => {
    setSection(name); setQuery("");
    if (name === "Vault" && vaultOpen) setSelectedId(vaultNote.id);
    else if (name !== "Vault" && name !== "Trash") setSelectedId(notes.find((note) => name !== "Pinned" || note.pinned)?.id || notes[0].id);
  };
  const toggleChecklist = (event) => {
    const target = event.target;
    if (!(target instanceof HTMLInputElement) || target.type !== "checkbox") return;
    const checkboxes = [...event.currentTarget.querySelectorAll('input[type="checkbox"]')];
    const index = checkboxes.indexOf(target);
    let seen = -1;
    changeMarkdown(markdown.replace(/- \[([ xX])\]/g, (match, state) => { seen += 1; return seen === index ? `- [${state.trim() ? " " : "x"}]` : match; }));
  };

  return <section className={capture ? "demo-section demo-section--capture" : "demo-section"} id="demo">
    {!capture && <div className="shell section-intro"><p className="eyebrow">Try the real shape of it</p><h2>A notebook you can actually explore.</h2><p>This browser demo uses realistic synthetic notes. Search, move between spaces, unlock the sample Vault, edit Markdown, and watch the Page view stay in sync.</p></div>}
    <div className={`app-stage ${dark ? "is-dark" : ""}`}>
      <div className="app-window" aria-label="Interactive Clasp demo">
        <div className="titlebar"><div className="traffic-lights" aria-hidden="true"><span /><span /><span /></div><button className="icon-button sidebar-button" aria-label="Toggle sidebar" onClick={() => setSidebarOpen((value) => !value)}><SidebarSimple /></button><div className="app-wordmark"><img src="/clasp-app-icon.png" alt="" /> Clasp</div><div className="titlebar-actions"><button className="icon-button" aria-label={dark ? "Use light preview" : "Use dark preview"} onClick={() => setDark((value) => !value)}>{dark ? <Sun /> : <Moon />}</button><button className="new-note"><NotePencil /> New note</button><label className="search-field"><MagnifyingGlass /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder={`Search ${section}`} /></label></div></div>
        <div className={`app-body ${sidebarOpen ? "" : "sidebar-closed"}`}>
          {sidebarOpen && <aside className="app-sidebar"><nav aria-label="Demo notebook sections">{navItems.map(([label, Icon]) => <button key={label} className={section === label ? "is-selected" : ""} onClick={() => selectSection(label)}><Icon /> {label}</button>)}</nav><p className="sidebar-label">Tags</p>{['thinking', 'today', 'reading', 'work'].map((tag) => <button className="tag-link" key={tag} onClick={() => setQuery(tag)}><Hash /> {tag}</button>)}<div className="local-badge"><ShieldCheck /><span><strong>Local by default</strong><small>No account required</small></span></div></aside>}
          <aside className="note-list"><div className="note-list-heading"><span>{section}</span><small>{filtered.length || "—"} notes</small></div>{section === "Vault" && !vaultOpen ? <div className="list-locked"><LockKey /><strong>Vault locked</strong><span>Unlock the sample to see a safe, synthetic note.</span></div> : filtered.length ? filtered.map((note) => <button key={note.id} onClick={() => setSelectedId(note.id)} className={selected?.id === note.id ? "note-card is-selected" : "note-card"}><span className="note-card-title">{note.pinned && <PushPin weight="fill" />} {note.title}</span><span>{note.preview}</span><small>{note.age} · {note.tags.join(", ")}</small></button>) : <div className="empty-list"><FileText /><span>{query ? "No notes match this search." : "Nothing here yet."}</span></div>}</aside>
          <main className="editor-pane">
            {section === "Vault" && !vaultOpen ? <div className="vault-locked"><ShieldCheck /><h3>Vault Locked</h3><p>Titles, tags, bodies, and search results stay unavailable until you authenticate.</p><button onClick={() => { setVaultOpen(true); setSelectedId(vaultNote.id); }}>Unlock sample Vault</button><small>Demo content only—no real credentials or secrets.</small></div> : selected ? <><div className="editor-header"><div><small>NOTE</small><h3>{selected.title}</h3></div><div className="mode-switch"><ModeButton active={mode === "page"} onClick={() => setMode("page")}>Page</ModeButton><ModeButton active={mode === "markdown"} onClick={() => setMode("markdown")}>Markdown</ModeButton></div></div><EditorToolbar mode={mode} textareaRef={textareaRef} markdown={markdown} onChange={changeMarkdown} /><div className="editor-canvas">{mode === "page" ? <article className="document-page" onClick={toggleChecklist}><ReactMarkdown remarkPlugins={[remarkGfm]} components={{ input: (props) => <input {...props} disabled={false} readOnly /> }}>{markdown}</ReactMarkdown></article> : <textarea ref={textareaRef} className="markdown-source" value={markdown} onChange={(event) => changeMarkdown(event.target.value)} spellCheck="false" aria-label="Markdown source" />}</div><div className="editor-footer"><span><Check /> Stored as Markdown</span><span>{selected.tags.join(" · ")}</span><span>Edited just now</span></div></> : <div className="vault-locked"><BookOpenText /><h3>Select a note</h3><p>Choose a note from the list to begin.</p></div>}
          </main>
        </div>
      </div>
    </div>
  </section>;
}

function SafetySection() {
  return <section className="safety-section shell" id="safety"><div className="safety-heading"><p className="eyebrow">Safety by design</p><h2>Your notes.<br />Under your control.</h2></div><div className="principles"><article><span>01</span><h3>Local by default</h3><p>No account, analytics profile, or mandatory cloud sync. Your regular notes remain portable Markdown files on your Mac.</p></article><article><span>02</span><h3>A focused Vault</h3><p>Use Vault for sensitive private notes that benefit from encrypted storage at rest and deliberate access.</p></article><article><span>03</span><h3>Self-custody, clearly</h3><p>Keep wallet procedures, research, and public-address labels close. Keep seed phrases, private keys, recovery codes, and signing credentials in a purpose-built key or password manager.</p></article></div><div className="safety-callout"><LockKey /><div><strong>Keep keys somewhere built for keys.</strong><span>Clasp helps you think, prepare, and document—without pretending to be a wallet.</span></div></div></section>;
}

function WhySection() {
  return <section className="why-section shell" id="why"><div className="why-copy"><p className="eyebrow">One source. Two ways to work.</p><h2>Markdown that reads like a document.</h2><p>Write directly in the source when precision matters. Switch to Page mode when you want calm typography and clean structure. Clasp keeps one canonical Markdown note underneath both.</p></div><div className="type-specimen"><span>PAGE / MARKDOWN</span><strong>Quiet.<br />Precise.<br />Readable.</strong><p>System-native controls.<br />Editorial document rhythm.<br />Portable source files.</p></div></section>;
}

function Footer() {
  return <footer id="help"><div className="shell footer-inner"><div className="wordmark"><BrandMark compact /><span>Clasp</span></div><p>Private Markdown notes for Mac.</p><div><a href="https://robertbmoore.github.io/clasp/">Support</a><a href="https://robertbmoore.github.io/clasp/privacy.html">Privacy</a><a href="#top">Back to top</a></div></div></footer>;
}

export function App() {
  const capture = new URLSearchParams(window.location.search).has("capture");
  return capture ? <DemoApp capture /> : <><Header /><Hero /><DemoApp /><WhySection /><SafetySection /><Footer /></>;
}
