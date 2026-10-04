from pathlib import Path

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs" / "Venture_Code_and_Security_Guide.docx"

BLUE = RGBColor(46, 116, 181)
DARK_BLUE = RGBColor(31, 77, 120)
INK = RGBColor(24, 34, 46)
MUTED = RGBColor(91, 103, 116)
PALE_BLUE = "E8EEF5"
PALE_GRAY = "F4F6F9"
WHITE = "FFFFFF"


def set_cell_shading(cell, fill):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = tc_pr.find(qn("w:shd"))
    if shd is None:
        shd = OxmlElement("w:shd")
        tc_pr.append(shd)
    shd.set(qn("w:fill"), fill)


def set_cell_width(cell, width_dxa):
    tc_pr = cell._tc.get_or_add_tcPr()
    tc_w = tc_pr.find(qn("w:tcW"))
    if tc_w is None:
        tc_w = OxmlElement("w:tcW")
        tc_pr.append(tc_w)
    tc_w.set(qn("w:w"), str(width_dxa))
    tc_w.set(qn("w:type"), "dxa")


def set_cell_margins(cell, top=80, start=120, bottom=80, end=120):
    tc_pr = cell._tc.get_or_add_tcPr()
    tc_mar = tc_pr.first_child_found_in("w:tcMar")
    if tc_mar is None:
        tc_mar = OxmlElement("w:tcMar")
        tc_pr.append(tc_mar)
    for edge, value in (("top", top), ("start", start), ("bottom", bottom), ("end", end)):
        node = tc_mar.find(qn(f"w:{edge}"))
        if node is None:
            node = OxmlElement(f"w:{edge}")
            tc_mar.append(node)
        node.set(qn("w:w"), str(value))
        node.set(qn("w:type"), "dxa")


def configure_table(table, widths):
    table.autofit = False
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl_pr = table._tbl.tblPr
    tbl_w = tbl_pr.find(qn("w:tblW"))
    if tbl_w is None:
        tbl_w = OxmlElement("w:tblW")
        tbl_pr.append(tbl_w)
    tbl_w.set(qn("w:w"), "9360")
    tbl_w.set(qn("w:type"), "dxa")
    tbl_ind = tbl_pr.find(qn("w:tblInd"))
    if tbl_ind is None:
        tbl_ind = OxmlElement("w:tblInd")
        tbl_pr.append(tbl_ind)
    tbl_ind.set(qn("w:w"), "120")
    tbl_ind.set(qn("w:type"), "dxa")
    grid = table._tbl.tblGrid
    for child in list(grid):
        grid.remove(child)
    for width in widths:
        grid_col = OxmlElement("w:gridCol")
        grid_col.set(qn("w:w"), str(width))
        grid.append(grid_col)
    for row in table.rows:
        for index, cell in enumerate(row.cells):
            set_cell_width(cell, widths[index])
            set_cell_margins(cell)
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER


def set_run(run, size=11, color=INK, bold=False, italic=False, font="Calibri"):
    run.font.name = font
    run._element.get_or_add_rPr().rFonts.set(qn("w:ascii"), font)
    run._element.get_or_add_rPr().rFonts.set(qn("w:hAnsi"), font)
    run.font.size = Pt(size)
    run.font.color.rgb = color
    run.bold = bold
    run.italic = italic


def add_page_number(paragraph):
    paragraph.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    run = paragraph.add_run("Page ")
    set_run(run, size=9, color=MUTED)
    fld_char = OxmlElement("w:fldChar")
    fld_char.set(qn("w:fldCharType"), "begin")
    instr_text = OxmlElement("w:instrText")
    instr_text.set(qn("xml:space"), "preserve")
    instr_text.text = " PAGE "
    fld_end = OxmlElement("w:fldChar")
    fld_end.set(qn("w:fldCharType"), "end")
    run._r.extend([fld_char, instr_text, fld_end])


def configure_document(doc):
    section = doc.sections[0]
    section.page_width = Inches(8.5)
    section.page_height = Inches(11)
    section.top_margin = Inches(1)
    section.right_margin = Inches(1)
    section.bottom_margin = Inches(1)
    section.left_margin = Inches(1)
    section.header_distance = Inches(0.492)
    section.footer_distance = Inches(0.492)

    normal = doc.styles["Normal"]
    normal.font.name = "Calibri"
    normal._element.rPr.rFonts.set(qn("w:ascii"), "Calibri")
    normal._element.rPr.rFonts.set(qn("w:hAnsi"), "Calibri")
    normal.font.size = Pt(11)
    normal.font.color.rgb = INK
    normal.paragraph_format.space_before = Pt(0)
    normal.paragraph_format.space_after = Pt(6)
    normal.paragraph_format.line_spacing = 1.25

    heading_specs = {
        "Heading 1": (16, BLUE, 18, 10),
        "Heading 2": (13, BLUE, 14, 7),
        "Heading 3": (12, DARK_BLUE, 10, 5),
    }
    for name, (size, color, before, after) in heading_specs.items():
        style = doc.styles[name]
        style.font.name = "Calibri"
        style._element.rPr.rFonts.set(qn("w:ascii"), "Calibri")
        style._element.rPr.rFonts.set(qn("w:hAnsi"), "Calibri")
        style.font.size = Pt(size)
        style.font.color.rgb = color
        style.font.bold = True
        style.paragraph_format.space_before = Pt(before)
        style.paragraph_format.space_after = Pt(after)
        style.paragraph_format.keep_with_next = True

    for list_name in ("List Bullet", "List Number"):
        style = doc.styles[list_name]
        style.font.name = "Calibri"
        style.font.size = Pt(11)
        style.paragraph_format.left_indent = Inches(0.375)
        style.paragraph_format.first_line_indent = Inches(-0.188)
        style.paragraph_format.space_after = Pt(4)
        style.paragraph_format.line_spacing = 1.25

    header = section.header.paragraphs[0]
    header.alignment = WD_ALIGN_PARAGRAPH.LEFT
    set_run(header.add_run("VENTURE  |  CODE AND SECURITY GUIDE"), size=9, color=MUTED, bold=True)
    add_page_number(section.footer.paragraphs[0])

    props = doc.core_properties
    props.title = "Venture Code and Security Guide"
    props.subject = "Architecture, data handling, capability boundaries, and product narrative"
    props.author = "Venture"
    props.keywords = "Venture, iOS, SwiftUI, HealthKit, privacy, security"


def add_title_page(doc):
    for _ in range(6):
        doc.add_paragraph()
    kicker = doc.add_paragraph()
    kicker.alignment = WD_ALIGN_PARAGRAPH.CENTER
    set_run(kicker.add_run("TECHNICAL REFERENCE"), size=10, color=BLUE, bold=True)
    kicker.paragraph_format.space_after = Pt(18)
    title = doc.add_paragraph()
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    set_run(title.add_run("venture"), size=34, color=INK, bold=True)
    title.paragraph_format.space_after = Pt(6)
    subtitle = doc.add_paragraph()
    subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
    set_run(subtitle.add_run("Code and Security Guide"), size=19, color=DARK_BLUE)
    subtitle.paragraph_format.space_after = Pt(12)
    deck = doc.add_paragraph()
    deck.alignment = WD_ALIGN_PARAGRAPH.CENTER
    set_run(deck.add_run("How the native iOS app measures personal change, protects stored metrics, and stays inside honest clinical boundaries"), size=11, color=MUTED)
    deck.paragraph_format.space_after = Pt(32)
    meta = doc.add_paragraph()
    meta.alignment = WD_ALIGN_PARAGRAPH.CENTER
    set_run(meta.add_run("Implementation snapshot  |  June 14, 2026  |  iOS 17+"), size=9.5, color=MUTED, bold=True)
    doc.add_page_break()


def add_bullets(doc, items):
    for item in items:
        paragraph = doc.add_paragraph(style="List Bullet")
        paragraph.add_run(item)


def add_status_table(doc, rows, widths=(2400, 1740, 5220)):
    table = doc.add_table(rows=1, cols=3)
    table.style = "Table Grid"
    configure_table(table, list(widths))
    headers = ("Capability", "Status", "What the code does")
    for index, header in enumerate(headers):
        set_cell_shading(table.rows[0].cells[index], PALE_BLUE)
        paragraph = table.rows[0].cells[index].paragraphs[0]
        paragraph.paragraph_format.space_after = Pt(0)
        set_run(paragraph.add_run(header), size=9.5, color=DARK_BLUE, bold=True)
    for capability, status, detail in rows:
        cells = table.add_row().cells
        for index, value in enumerate((capability, status, detail)):
            paragraph = cells[index].paragraphs[0]
            paragraph.paragraph_format.space_after = Pt(0)
            set_run(paragraph.add_run(value), size=9.2, color=INK, bold=index == 1)
    configure_table(table, list(widths))
    return table


def add_callout(doc, title, body):
    table = doc.add_table(rows=1, cols=1)
    table.style = "Table Grid"
    configure_table(table, [9360])
    cell = table.cell(0, 0)
    set_cell_shading(cell, PALE_GRAY)
    paragraph = cell.paragraphs[0]
    paragraph.paragraph_format.space_after = Pt(3)
    set_run(paragraph.add_run(title + "\n"), size=10.5, color=DARK_BLUE, bold=True)
    set_run(paragraph.add_run(body), size=10, color=INK)


def build_document():
    doc = Document()
    configure_document(doc)
    add_title_page(doc)

    doc.add_heading("1. Executive summary", level=1)
    doc.add_paragraph(
        "Venture is a native SwiftUI application that records short, permission-gated measurements and compares them with the same user's prior measurements. Its current implementation measures camera-derived eye and pupil features, guided voice timing, memory and attention task performance, Apple Health recovery signals, and imported Apple Watch ECG data."
    )
    add_callout(
        doc,
        "Clinical boundary",
        "Venture does not determine whether a user has Alzheimer's disease, Parkinson's disease, depression, or any other neurological, psychiatric, or cardiac condition. It reports measured values, personal-reference change, and Apple's own Watch ECG classification."
    )
    doc.add_heading("Current product loop", level=2)
    add_bullets(doc, [
        "Open the app and complete permission setup.",
        "Run the pupil, guided voice, memory, and attention measurements; individual steps can be skipped.",
        "Read the measured values and personal signal-load estimate on Home and Insights.",
        "Import Apple Health and the latest Apple Watch ECG when available.",
        "Ask the local companion to explain exact values or activate user-selected Screen Time protection.",
    ])
    doc.add_heading("What changed in this implementation", level=2)
    add_bullets(doc, [
        "The reaction-time task and the Future tab were removed.",
        "The mental health core now calculates one bounded personal signal-load estimate only after at least three earlier measured days.",
        "ECG import refreshes the core immediately; deleting a history recomputes the score instead of preserving a stale result.",
        "The assistant uses Apple's on-device Foundation Models runtime on eligible iOS 26 devices and a deterministic local metric explainer elsewhere.",
    ])
    doc.add_page_break()

    doc.add_heading("2. Architecture and data flow", level=1)
    doc.add_paragraph(
        "The app is organized around a small observable store. Sensor services publish measurements, the store creates a CognitiveSnapshot, MentalHealthCore compares the latest snapshot with up to 14 prior snapshots, and SecureMetricsStore encrypts the resulting metrics before writing them to Application Support."
    )
    add_status_table(doc, [
        ("User interface", "Implemented", "SwiftUI onboarding, Home, Insights, scan flow, account center, local companion, and focus-protection settings."),
        ("State coordination", "Implemented", "VentureStore owns snapshot history, HealthKit state, scoring, deletion, and encrypted persistence."),
        ("Background work", "Implemented", "VentureJobPipeline coalesces delayed persistence jobs so rapid UI updates do not cause repeated writes."),
        ("Cloud backend", "Not present", "This build has no cloud sync service and no remote inference endpoint."),
        ("Authentication", "Prototype", "Apple-, Google-, and email-styled entry controls currently advance locally; they are not production identity providers."),
    ])
    doc.add_heading("Stored record", level=2)
    doc.add_paragraph(
        "Each CognitiveSnapshot can contain fixation stability, pupil response, pupil symmetry, pupil variability, speech timing stability, voice activity ratio, background-noise estimate, HRV, sleep hours, memory score, attention score, timestamp, and the calculated personal signal-load value. Missing permissions or skipped tasks remain nil rather than being filled with demo data."
    )
    doc.add_heading("No seeded or placebo measurements", level=2)
    doc.add_paragraph(
        "A new store starts empty. Schema version 4 rejects older prototype persistence that may have contained seeded values. The UI presents unavailable or learning-baseline states until real measurements exist."
    )
    doc.add_page_break()

    doc.add_heading("3. Measurement implementations", level=1)
    doc.add_heading("Eye and pupil path", level=2)
    doc.add_paragraph(
        "EyeTrackingService uses the front camera and Apple's Vision face-landmark request. The capture connection is rotated to portrait and mirrored horizontally. The app draws the detected face and eye contours over the scan experience, estimates fixation stability from normalized eye-center movement, and counts blink transitions from eye aspect ratio."
    )
    doc.add_paragraph(
        "For pupil response, the service collects a baseline phase followed by a bright-screen phase. It crops each landmark-defined eye region, renders a 48 by 24 luminance image, estimates the dark central region, and calculates a relative diameter. The reported response is the proportional change between robust baseline and bright-phase means. This is a camera estimate, not calibrated pupillometry and not a stress or disease detector."
    )
    doc.add_heading("Guided voice path", level=2)
    doc.add_paragraph(
        "VoiceCaptureService records a fixed reading prompt through AVAudioEngine, requests partial Apple Speech transcription, highlights matched prompt words, and automatically finishes when the prompt is complete. Silero VAD Core ML analyzes 16 kHz audio chunks for voice-activity ratio and background-noise estimates. Speech timing stability is derived from recognized segment durations and long pauses."
    )
    doc.add_paragraph(
        "A temporary CAF file is created only during capture, closed on stop, and deleted immediately. The app persists extracted metrics, not the recording. Apple's voice-processing mode is used for supported echo and noise suppression."
    )
    doc.add_heading("Cognition path", level=2)
    doc.add_paragraph(
        "The cognitive scan contains working-memory and attention-switching interactions. Scores come from task performance. The removed reaction-time task is no longer part of the scan, score, UI, or test fixtures."
    )
    doc.add_heading("Apple Health and ECG", level=2)
    doc.add_paragraph(
        "HealthService requests read-only HealthKit access for HRV, resting heart rate, oxygen saturation, steps, active energy, sleep analysis, and electrocardiograms. The latest Watch ECG query imports metadata, Apple's classification, symptoms, source, and available lead-I voltage samples. Venture displays the waveform but does not reinterpret it."
    )
    doc.add_page_break()

    doc.add_heading("4. Mental health core", level=1)
    doc.add_paragraph(
        "MentalHealthCore is a personal-change engine, not a diagnostic engine. It evaluates four domains: memory and attention, voice change, pupil and recovery, and Apple Watch ECG. The latest measurement is compared with up to 14 earlier snapshots from the same user."
    )
    doc.add_heading("Score requirements", level=2)
    add_bullets(doc, [
        "At least three earlier snapshots are required before a score is emitted.",
        "Only signals with both a latest value and a usable personal baseline contribute.",
        "Each deviation is normalized and clamped from 0 to 1; the mean is converted to a 0-100 personal signal-load estimate.",
        "Missing measurements remain unavailable and do not add artificial severity.",
        "The score is recalculated after scan completion, HealthKit refresh, ECG import, or history deletion.",
    ])
    doc.add_heading("Domain interpretation", level=2)
    add_status_table(doc, [
        ("Memory and attention", "Personal change", "Looks for drops from the user's earlier task scores and recommends repeat measurement or clinician review if changes persist."),
        ("Voice", "Personal change", "Looks for a drop in guided-reading timing stability. It does not classify Parkinson's disease, depression, or dementia."),
        ("Pupil and recovery", "Personal change", "Combines relative pupil-response change, sleep deviation, and HRV deviation when baselines exist."),
        ("Watch ECG", "Apple result", "Shows Apple's classification. Atrial fibrillation triggers clinician guidance; no extra condition labels are inferred."),
    ])
    add_callout(
        doc,
        "Why the requested disease labels are not implemented",
        "Phone camera, microphone, task, and Watch data can be noisy and confounded by sleep, language, environment, medication, hardware, and user behavior. The cited research checkpoints do not provide validated yes/no diagnosis for this deployment. Presenting those outputs as disease status would create false reassurance or unnecessary alarm."
    )
    doc.add_page_break()

    doc.add_heading("5. Local companion and interventions", level=1)
    doc.add_heading("On-device companion", level=2)
    doc.add_paragraph(
        "AdaptiveCompanionEngine uses Apple's Foundation Models framework when SystemLanguageModel reports availability on iOS 26. The model receives only recent Venture snapshots, current HealthKit values, mental-core assessments, and Screen Time state assembled in memory. The system prompt prohibits diagnosis, additional ECG inference, certainty language, and unsupported values."
    )
    doc.add_paragraph(
        "On devices without the eligible Apple runtime, MetricCompanionEngine produces local rule-based answers. It supports distinct ECG, sleep, voice, pupil, privacy, Screen Time, disease-boundary, crisis, and overall-summary responses. It cites exact available values and explicitly says when data is missing."
    )
    doc.add_heading("Focus protection", level=2)
    doc.add_paragraph(
        "CognitiveSupportService uses FamilyControls and ManagedSettings. The user must authorize Screen Time and explicitly select applications, categories, or web domains. Venture can then shield those selected items, stop protection, and schedule a local wind-down notification. Optional low-sleep automation can activate only after the user has enabled it and selected items."
    )
    add_callout(
        doc,
        "Operating-system boundary",
        "Venture cannot silently change another app's notification settings, create arbitrary Screen Time limits without authorization, or guarantee Family Controls access. Distribution requires Apple's Family Controls entitlement approval, and behavior must be validated on a physical device."
    )
    doc.add_heading("Crisis handling", level=2)
    doc.add_paragraph(
        "Both assistant paths route self-harm or immediate-danger language to 988 in the United States or emergency services. Venture does not present itself as crisis care."
    )
    doc.add_page_break()

    doc.add_heading("6. Security and privacy", level=1)
    doc.add_heading("Data at rest", level=2)
    add_bullets(doc, [
        "SecureMetricsStore JSON-encodes the state and seals it with CryptoKit AES-GCM using a 256-bit symmetric key.",
        "The key is stored in Keychain as a generic password item with kSecAttrAccessibleWhenUnlockedThisDeviceOnly, preventing migration to another device through backup.",
        "The encrypted metrics file uses atomic writes and complete file protection in the app's Application Support directory.",
        "The persisted history is capped at the most recent 365 snapshots.",
    ])
    doc.add_heading("Source-media lifecycle", level=2)
    add_bullets(doc, [
        "Camera frames are delivered as sample buffers, analyzed in memory, and never written by EyeTrackingService.",
        "VoiceCaptureService writes a temporary CAF only while recording, then deletes it on stop or failure.",
        "Only extracted eye, voice, cognition, recovery, and ECG metrics are placed in encrypted persistence.",
    ])
    doc.add_heading("Permissions and entitlements", level=2)
    add_status_table(doc, [
        ("Camera", "User permission", "Required only for the eye and pupil scan."),
        ("Microphone and Speech", "User permission", "Required only for the guided reading and word highlighting."),
        ("HealthKit", "Read-only", "Reads selected recovery and ECG types; Venture requests no write types."),
        ("Family Controls", "Entitlement + consent", "Shields only user-selected distractions after authorization."),
        ("Face ID", "User permission", "Protects app access; metrics encryption does not depend on biometric success."),
    ])
    doc.add_heading("Current security gaps", level=2)
    doc.add_paragraph(
        "The current build has prototype authentication controls and no production account server, JWT rotation, encrypted cloud sync, device revocation service, or audit-log backend. Those capabilities must not be advertised until a real identity and server architecture is implemented and reviewed."
    )
    doc.add_heading("Deletion controls", level=2)
    doc.add_paragraph(
        "The account center can remove eye history, voice history, Health history, or all scans. Each operation updates the in-memory snapshots, recalculates the personal score from the remaining fields, and schedules a replacement encrypted state. Clearing every scan returns the app to an unmeasured baseline-learning state."
    )
    doc.add_heading("Threat model summary", level=2)
    add_bullets(doc, [
        "A copied metrics file is not useful without the separate device-bound Keychain key.",
        "A device that is already unlocked and running compromised software remains outside the protection CryptoKit can provide; platform security and app review still matter.",
        "Temporary microphone media is minimized but exists during an active recording session, so interruption and crash-path testing are required before release.",
        "HealthKit and Family Controls data remain subject to Apple's permission, entitlement, backup, and device-policy boundaries.",
    ])
    doc.add_page_break()

    doc.add_heading("7. Capability matrix", level=1)
    add_status_table(doc, [
        ("Horizontal eye/pupil tracking", "Implemented", "Portrait-rotated front-camera feed, mirrored coordinates, Vision contours, fixation, blink, and relative pupil response."),
        ("Guided voice capture", "Implemented", "Real microphone recording, live waveform level, local VAD, prompt progress, timing metrics, and temporary-file deletion."),
        ("Memory and attention tasks", "Implemented", "Interactive task-derived scores; reaction time removed."),
        ("Apple Health recovery", "Implemented", "Read-only HRV, sleep, resting heart rate, oxygen saturation, steps, and active energy."),
        ("Latest Watch ECG", "Implemented", "Imports HealthKit ECG metadata, Apple classification, and available voltage samples."),
        ("Multi-condition ECG diagnosis", "Not implemented", "HuBERT-ECG base is not a ready-to-use validated condition classifier."),
        ("Alzheimer's status", "Not determined", "No validated diagnostic model or clinical workflow is present."),
        ("Parkinson's status", "Not determined", "Voice timing and tremor-adjacent measurements are not disease classification."),
        ("Depression status", "Not determined", "No validated diagnostic interview, clinical model, or professional assessment is present."),
        ("Personal signal load", "Implemented", "Bounded estimate from same-user deviations after sufficient history."),
        ("Local generative assistant", "Implemented", "Bundled Qwen 2.5 0.5B GGUF through llama.cpp, with measured-context grounding and deterministic safety fallback."),
        ("Screen Time protection", "Device dependent", "Requires Family Controls entitlement, user authorization, and explicit selection."),
    ])
    doc.add_heading("Model-source boundary", level=2)
    doc.add_paragraph(
        "Silero VAD Core ML and Qwen 2.5 0.5B GGUF are bundled for local inference. Apple Vision, Speech, HealthKit, Foundation Models, FamilyControls, and ManagedSettings provide platform capabilities. MediaPipe, DeepFilterNet3, SSL4PR, WavBERT, Depression-Engine, and HuBERT-ECG are not represented as running disease models in this build."
    )
    doc.add_page_break()

    doc.add_heading("8. Verification and code map", level=1)
    doc.add_heading("Primary files", level=2)
    add_status_table(doc, [
        ("VentureStore.swift", "State", "Measurement history, score refresh, HealthKit ingestion, deletion, and persistence scheduling."),
        ("EyeTrackingService.swift", "Camera", "Vision eye landmarks, fixation, blink, and relative pupil calculations."),
        ("VoiceCaptureService.swift", "Audio", "Recording, Apple Speech progress, timing metrics, and source-file deletion."),
        ("HealthService.swift", "HealthKit", "Recovery queries, observers, latest ECG query, classification, and waveform import."),
        ("MentalHealthCore.swift", "Scoring", "Same-user baseline comparison and four domain assessments."),
        ("AdaptiveCompanionEngine.swift", "Assistant", "Foundation Models availability check, grounded prompt, and fallback routing."),
        ("CognitiveSupportService.swift", "Protection", "Family Controls authorization, Managed Settings shields, and wind-down notification."),
        ("SecureMetricsStore.swift", "Security", "AES-GCM persistence and Keychain key management."),
    ], widths=(3000, 1500, 4860))
    doc.add_heading("Verification expectations", level=2)
    add_bullets(doc, [
        "Run unit tests for empty-state behavior, deletion, companion grounding, score prerequisites, score bounds, HealthKit mapping, and Apple atrial-fibrillation escalation.",
        "Run the app on Simulator for navigation, empty states, animations, memory/attention flow, assistant fallback, and layout inspection.",
        "Use a physical iPhone for camera, microphone, brightness, biometric, HealthKit, and Family Controls validation.",
        "Use a paired, compatible Apple Watch with an existing ECG recording to validate voltage-sample import and Apple's classification display.",
        "Do not convert unavailable hardware paths into sample values for demos; show an explicit setup-needed state instead.",
    ])
    doc.add_page_break()

    doc.add_heading("9. Product narrative", level=1)
    doc.add_heading("Inspiration", level=2)
    doc.add_paragraph(
        "Venture started with my grandfather. He lived with Alzheimer disease, and our family watched his mind change gradually in ways we did not understand at the time. Small shifts in memory and attention passed unnoticed. That experience motivated an app that helps people observe their own changes earlier without pretending a phone can provide a diagnosis."
    )
    doc.add_heading("What it does", level=2)
    doc.add_paragraph(
        "Venture learns a personal reference across pupil, voice, cognition, recovery, and available Watch signals. Short interactive scans and daily HealthKit patterns become a personal signal-load estimate, evidence showing what changed, and a focused action such as protecting selected distractions or improving wind-down timing."
    )
    doc.add_heading("How we built it", level=2)
    doc.add_paragraph(
        "Venture is a native SwiftUI experience with soft motion, curved controls, and an orb-based entrance. Underneath, camera processing, guided audio, cognitive tasks, HealthKit, encrypted storage, on-device explanation, and Screen Time controls feed one consistent measurement timeline."
    )
    doc.add_heading("Challenges", level=2)
    doc.add_paragraph(
        "The hardest problem is staying honest about what the signals can and cannot establish. Sleep, stress, hardware, language, environment, and behavior all affect measurements. Venture therefore reports personal trends and explicit uncertainty rather than hard disease labels. Permission flows and device-only APIs also require careful fallback states and physical-device testing."
    )
    doc.add_heading("Accomplishments", level=2)
    doc.add_paragraph(
        "The app collects real task and sensor outputs without manual journaling, keeps raw camera data out of storage, deletes temporary voice audio, imports real Apple Health and Watch data, and explains available values locally. Missing data remains visible as missing rather than being replaced with placebo output."
    )
    doc.add_heading("What we learned", level=2)
    doc.add_paragraph(
        "Early cognitive and wellbeing changes are subtle and noisy. A responsible product must distinguish a measurement from an interpretation, compare a person with their own history, and make escalation language clear without causing false certainty."
    )
    doc.add_heading("What is next", level=2)
    doc.add_paragraph(
        "The next technical step is prospective validation: compare Venture's repeatability and personal-change metrics with formal cognitive tests and real-world outcomes under researcher oversight. Production identity, entitlement approval, accessibility testing, device performance profiling, and a reviewed clinical-safety process are also required before broad release."
    )
    doc.add_heading("Release gates", level=2)
    add_bullets(doc, [
        "Validate camera, brightness, audio, HealthKit, Watch ECG, biometric, and Family Controls paths on supported physical hardware.",
        "Profile launch, scan, Core ML, camera, and assistant memory use on the oldest supported iPhone class.",
        "Complete accessibility, interruption, denied-permission, low-storage, offline, and battery-impact testing.",
        "Replace prototype entry controls with reviewed production identity or remove account claims entirely.",
        "Obtain independent privacy, security, clinical-safety, and research-method review before making outcome claims.",
    ])

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    doc.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    build_document()
