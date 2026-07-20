# FRANTOIO GEST v0.1

Gestione frantoio multi-azienda — Supabase + Vercel.
Port da Cantina Gest v0.1. **Logica tracciabilità lotti invariata.**

## Delta rispetto a Cantina

| | Cantina | Frantoio |
|---|---|---|
| Movimenti | litri | **litri** (invariato) |
| Giacenze | litri | **litri + kg** (ogni riga, ogni KPI, ogni totale) |
| Densità | — | **0.916** kg/L, per-azienda |
| Anagrafica prodotto | varietà uva | **qualità olio** (9: ITALICO/NP/CASALIVA × BIO, DOP) |
| Vasi | 70 vasche | **88** (BATTENTE, INOX, BIDONE, CUBO, PRIVATI…) |
| Analisi | 14 param. enologici | acidità, perossidi, polifenoli, K232/K270/ΔK, alchil esteri |
| Operazioni | +imbottigliamento | +**filtrazione** |

## Decisione tecnica: i kg NON sono stoccati

`kg` e `capacita_kg` sono **GENERATED ALWAYS ... STORED**:

```sql
kg NUMERIC(10,2) GENERATED ALWAYS AS (ROUND(litri * 0.916, 2)) STORED
```

Se li salvassi come colonne normali, alla prima rettifica litri e kg
divergerebbero e non sapresti più quale delle due è vera. Così Postgres
garantisce che siano sempre coerenti: **una sola fonte di verità = i litri.**

Anche il frontend non tiene mai i kg in stato: li calcola al render
(`L2KG = l => l * DENSITA`).

⚠️ La densità nel `GENERATED` è hard-coded a `0.916` (Postgres non accetta
sottoquery nelle generated column). `frantoio_aziende.densita` governa il
**frontend**. Se un domani ti serve una densità diversa *a livello DB*, va
fatto un `ALTER ... DROP/ADD COLUMN` — oppure si sostituiscono le generated
con una VIEW. Per ora 0.916 è unico e va bene così.

## Stack
- **Frontend**: `index.html` singolo file, nessuna build
- **Backend**: Supabase (progetto condiviso `fysrnwybfhtmjvthljuz`, prefisso `frantoio_`)
- **Auth**: Supabase Auth email+password
- **Deploy**: Vercel (statico)

## Setup

### 1. Database
SQL Editor di Supabase → esegui `frantoio-schema-v1_0.sql`.
(Include già la patch bootstrap-login: **non serve** un file patch a parte.)
Crea 8 tabelle, RLS completo, 9 qualità e **88 vasche** già seedate dal tuo XLSX.

### 2. Anon key
In `index.html` sostituisci `INCOLLA_QUI_LA_ANON_KEY` con la anon key
(Dashboard → Settings → API → `anon public`).

> ⚠️ La chiave del progetto Cantina è stata esposta in chat: rigenerala
> in Supabase e usa la nuova ovunque (Cantina, Bollicine, Frantoio).

### 3. Primo utente
Authentication → Users → **Add user** → `andrea@agririva.it` + password,
spunta "Auto Confirm User". Il record in `frantoio_utenti` esiste già
(seed, ruolo `super_admin`); al primo login l'app collega `auth_uid`.

### 4. Deploy
```bash
git init && git add . && git commit -m "Frantoio Gest v0.1"
gh repo create FRANTOIO-GEST --private --source=. --push
```
Vercel → New Project → framework "Other", nessuna build, output = root.

## Nuova azienda (solo super_admin)
```sql
INSERT INTO frantoio_aziende (nome, email, densita)
VALUES ('Frantoio Rossi', 'info@rossi.it', 0.916);
-- id restituito, es. 2
INSERT INTO frantoio_qualita (azienda_id, codice, nome, sigla)
VALUES (2, 'ITALICO', 'ITALICO', 'IT');
INSERT INTO frantoio_vasche (azienda_id, numero, codice, materiale, capacita_litri)
VALUES (2, 1, 'S1', 'INOX', 1000);
INSERT INTO frantoio_utenti (azienda_id, email, nome, ruolo)
VALUES (2, 'operatore@rossi.it', 'Mario', 'operatore');
```

## Cosa c'è / cosa manca in v0.1
✅ Vasche (88), qualità (9), operazioni (carico/travaso/colmatura/filtrazione/
   imbottigliamento/perdita/vendita/riclassifica), rettifica inventario con
   preview delta L+kg, log, giacenze pivot per qualità, tracciabilità lotti
   proporzionale, coda offline, multi-azienda, densità configurabile da UI

⏸ Analisi olio (tabella pronta + tab con parametri e limiti → UI inserimento v0.2)
⏸ Conferimenti / molitura (rese olive→olio, conto terzi sui vasi PRIVATI → v0.2)
⏸ Report email (Edge Function → v0.2)

## Note sui vasi PRIVATI
18 vasi (`P01`–`P16`, `PXX`, `CIST COMAI`) sono marcati `PRIVATI` = olio conto
terzi. `frantoio_lotti.conferente` è già in schema per legarli al proprietario,
ma la UI conto-terzi arriva in v0.2 insieme ai conferimenti.
