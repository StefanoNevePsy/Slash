"""Builds docs/Slash-Guida.pdf (Italian user guide). Run: python3 scripts/make-guide.py"""
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.fonts import addMapping
from reportlab.lib.pagesizes import A4
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib import colors
from reportlab.lib.units import cm

D = '/usr/share/fonts/truetype/dejavu/'
pdfmetrics.registerFont(TTFont('DV', D + 'DejaVuSans.ttf'))
pdfmetrics.registerFont(TTFont('DVB', D + 'DejaVuSans-Bold.ttf'))
addMapping('DV', 0, 0, 'DV'); addMapping('DV', 1, 0, 'DVB'); addMapping('DV', 0, 1, 'DV'); addMapping('DV', 1, 1, 'DVB')

ss = getSampleStyleSheet()
H1 = ParagraphStyle('h1', parent=ss['Title'], fontName='DVB', textColor=colors.HexColor('#2D6FEB'))
H2 = ParagraphStyle('h2', parent=ss['Heading2'], fontName='DVB', textColor=colors.HexColor('#1A2240'), spaceBefore=10)
B = ParagraphStyle('b', parent=ss['BodyText'], fontName='DV', fontSize=10, leading=14.5)
P = lambda t: Paragraph(t, B)

story = [Image('Resources/AppIcon.png', 3 * cm, 3 * cm), Paragraph('Slash — Guida rapida', H1),
         P('Slash è un file manager nativo per Mac: lavora sui file e le cartelle che hai già, accanto al Finder, e usa le '
           '<b>stesse scorciatoie del Finder</b>. Tutto ciò che aggiungi (proprietà, nickname, icone, viste) resta solo in Slash.')]

sections = [
    ('1. Installazione e aggiornamenti', [
        'Scarica <b>Slash.zip</b> dalla pagina Releases su GitHub, aprilo e trascina Slash in Applicazioni.',
        'Primo avvio: tasto destro sull\'app → <b>Apri</b> (l\'app non è notarizzata da Apple).',
        'Gli aggiornamenti sono automatici (all\'avvio e ogni 6 ore). Manuale: <b>Slash → Check for Updates…</b>; '
        'per disattivarli: <b>Slash → Impostazioni</b>.']),
    ('2. Viste: Icone, Elenco, Colonne', [
        '<b>⌘1</b> Icone, <b>⌘2</b> Elenco, <b>⌘3</b> Colonne (o i tre pulsanti in alto nel pannello).',
        'In Elenco clicca le intestazioni <b>Nome / Data modifica / Dimensione / Tipo</b> per ordinare; un secondo clic inverte l\'ordine.',
        'In Colonne ogni cartella selezionata apre una colonna a destra; selezionando un file compare l\'anteprima con le date.']),
    ('3. Ordinare e raggruppare', [
        'Menu <b>Vista → Sort By</b>: Nome, Tipo, Ultima apertura, Data aggiunta, Data modifica, Data creazione, Dimensione, Tag '
        '(<b>⌃⌥⌘1…7</b> come nel Finder).',
        '<b>⌃⌘0</b> attiva/disattiva i gruppi; <b>Vista → Group By</b> (⌃⌘2…7) raggruppa per tipo, date ("Oggi", "Ieri", "Ultimi 7 giorni"…), '
        'dimensione o tag del Finder, oppure per una proprietà di Slash.',
        '<b>⌘J</b> apre le opzioni vista: puoi salvare <b>più viste</b> della stessa cartella, filtrare per proprietà, mostrare i file nascosti (<b>⇧⌘.</b>).']),
    ('4. Lavorare sui file (come nel Finder)', [
        '<b>Invio</b> rinomina, <b>⌘O</b> o <b>⌘↓</b> apre, <b>Spazio</b> anteprima Quick Look, <b>⌘I</b> Informazioni.',
        '<b>⌘C</b> copia, <b>⌘V</b> incolla, <b>⌥⌘V</b> sposta qui, <b>⌘D</b> duplica, <b>⌘⌫</b> cestino, <b>⇧⌘N</b> nuova cartella, '
        '<b>⌃⌘A</b> crea alias, <b>⌘A</b> seleziona tutto.',
        '<b>⌘F</b> cerca: nella cartella corrente o anche nelle sottocartelle.',
        'Trascina file su un pannello o su un tab per spostarli (con <b>⌥</b> li copi).']),
    ('5. Pannelli affiancati e tab', [
        '<b>⌘\\</b> divide la finestra: fino a 4 cartelle affiancate. Il pannello attivo ha una linea blu in alto.',
        'Ogni pannello ha i suoi tab: <b>⌘T</b> nuovo, <b>⌘W</b> chiude. Tasto destro → <b>Copia / Sposta nell\'altro pannello</b>.']),
    ('6. Andare alle cartelle', [
        '<b>⌘[</b> / <b>⌘]</b> indietro/avanti, <b>⌘↑</b> cartella superiore, clic sul percorso in alto.',
        '<b>⇧⌘H</b> Home, <b>⇧⌘D</b> Scrivania, <b>⇧⌘O</b> Documenti, <b>⌥⌘L</b> Download, <b>⇧⌘I</b> iCloud Drive, '
        '<b>⇧⌘A</b> Applicazioni, <b>⇧⌘G</b> Vai alla cartella, <b>⌘K</b> Connetti al server.',
        '<b>⌥⌘K</b> apre la <b>Command Palette</b>: scrivi poche lettere del nome (es. "relros" trova "Relazioni Rossi").']),
    ('7. Spaces, cartelle fissate e icone', [
        'Uno <b>Space</b> è un\'area di lavoro per progetto (es. "Studio", "Formazione"): lo scegli o lo crei dal menu in cima alla barra laterale.',
        'Trascina una cartella in <b>Pinned</b> per fissarla. <b>Live · Recent changes</b> mostra i file modificati negli ultimi 7 giorni.',
        'Tasto destro su una cartella → <b>Set Icon…</b> per darle un\'icona e un colore (funziona anche su Google Drive).']),
    ('8. Proprietà e nickname', [
        'Tasto destro → <b>Status</b> (o altre proprietà) per etichettare i file (es. "Da revisionare / Inviato"). Le proprietà seguono il file se lo sposti o rinomini in Slash.',
        'Tasto destro → <b>Set Nickname…</b> per un nome leggibile senza rinominare davvero il file.',
        'Immagini: tasto destro → <b>Image</b> → capovolgi, ruota, converti in PNG/JPEG.']),
    ('9. Sicurezza: Annulla, copie, ricerca', [
        '<b>⌘Z</b> annulla l\'ultima operazione sui file (spostamento, copia, cestino, rinomina, nuova cartella…).',
        'Copie e spostamenti lunghi mostrano una barra di avanzamento in basso, con <b>Stop</b>. Se un file esiste già scegli '
        '<b>Mantieni entrambi / Sostituisci / Salta</b>, anche "per tutti".',
        'Alla riapertura Slash ritrova pannelli e tab come li avevi lasciati.',
        '<b>⌘F</b> → "Subfolders &amp; contents" cerca anche <b>dentro</b> PDF e documenti (Spotlight).']),
    ('10. Ordine: modelli, rinomina, cartelle intelligenti', [
        '<b>Modelli di cartelle</b>: menu ⋯ o File → <b>New Folder from Template</b> (es. "Nuovo caso" con Anamnesi, Test, Relazioni…). '
        'Si modificano in <b>Impostazioni → Templates</b>.',
        '<b>Rinomina multipla</b>: seleziona più file → tasto destro → <b>Rename N Items…</b>. Schema con {date}, {name}, {n}, {today}, {folder}, '
        'oppure Trova/Sostituisci, con anteprima.',
        '<b>Cartelle intelligenti</b>: <b>+</b> accanto a "Smart Folders" nella barra laterale (es. tutti i file con Status = Da revisionare).',
        '<b>Overview</b> (icona casa in alto): pagina dello Space con cartelle, link, note e impostazione privacy.',
        '<b>Elementi collegati</b>: menu ⋯ → <b>Related</b> per collegare cartelle (es. Drive ↔ locale) e link web.']),
    ('11. Strumenti in più', [
        '<b>⌘4</b> Galleria, <b>⇧⌘P</b> pannello anteprima (nei PDF puoi cercare nel testo).',
        'Tasto destro: <b>Open With</b>, <b>Share</b> (AirDrop, Mail, Messaggi), <b>Compress</b>, <b>PDF</b> → unisci / dividi in pagine, '
        '<b>Image</b> → Create PDF, <b>Delete Immediately</b>.',
        '<b>Promemoria</b>: tasto destro → <b>Remind Me…</b>; arriva una notifica e il file compare in "Reminders" nella barra laterale.',
        '<b>Note di cartella</b>: icona nota nella barra del percorso.',
        '<b>Download</b>: gli ultimi file scaricati sono nella barra laterale; in <b>Impostazioni → Downloads</b> crei regole '
        '(es. PDF con "relazione" nel nome → cartella Relazioni) che spostano i file automaticamente.',
        '<b>Space privato</b>: in Overview attiva "Private Space": si apre con Touch ID, non compare nelle condivisioni schermo '
        'e si richiude quando il Mac va in stop.',
        '<b>Sincronizzazione</b> tra Mac: Impostazioni → General → Sync (via iCloud Drive).']),
]
for title, items in sections:
    story.append(Paragraph(title, H2))
    for i in items:
        story.append(P('• ' + i)); story.append(Spacer(1, 2))

story.append(Paragraph('Scorciatoie principali', H2))
rows = [['Tasti', 'Azione', 'Tasti', 'Azione'],
        ['⌘1 / ⌘2 / ⌘3', 'Icone / Elenco / Colonne', '⌘C / ⌘V', 'Copia / Incolla'],
        ['⌘J', 'Opzioni vista', '⌥⌘V', 'Sposta qui'],
        ['⌃⌘0', 'Usa gruppi', '⌘D', 'Duplica'],
        ['⌃⌥⌘1…7', 'Ordina per…', '⌘⌫', 'Sposta nel cestino'],
        ['⇧⌘.', 'File nascosti', 'Invio', 'Rinomina'],
        ['⌘\\', 'Dividi pannello', '⌘I', 'Informazioni'],
        ['⌘T / ⌘W', 'Nuovo / chiudi tab', '⇧⌘N', 'Nuova cartella'],
        ['⌘[  ⌘]  ⌘↑', 'Indietro / avanti / su', '⌘F', 'Cerca'],
        ['⇧⌘G', 'Vai alla cartella', '⌥⌘K', 'Command Palette'],
        ['⌘K', 'Connetti al server', 'Spazio', 'Quick Look'],
        ['⌘4', 'Galleria', '⇧⌘P', 'Pannello anteprima'],
        ['⌘Z', 'Annulla', 'Invio', 'Rinomina']]
tb = Table(rows, colWidths=[2.8 * cm, 5.2 * cm, 2.8 * cm, 5.2 * cm])
tb.setStyle(TableStyle([('FONTNAME', (0, 0), (-1, -1), 'DV'), ('FONTNAME', (0, 0), (-1, 0), 'DVB'),
                        ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#2D6FEB')), ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
                        ('GRID', (0, 0), (-1, -1), 0.4, colors.HexColor('#CCCCCC')),
                        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, colors.HexColor('#F2F5FC')]), ('FONTSIZE', (0, 0), (-1, -1), 9.5)]))
story.append(tb)
SimpleDocTemplate('docs/Slash-Guida.pdf', pagesize=A4, leftMargin=2 * cm, rightMargin=2 * cm, topMargin=1.6 * cm,
                  bottomMargin=1.6 * cm, title='Slash — Guida rapida').build(story)
