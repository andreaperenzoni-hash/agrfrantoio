-- ═══════════════════════════════════════════════════════════════════════════
--  FRANTOIO GEST — schema v1.0
--  Port da cantina-schema v2.1 + patch v2.2 (già incorporata).
--
--  DELTA FRANTOIO:
--   • frantoio_aziende.densita  → default 0.916 (kg per litro di olio)
--   • MOVIMENTI  : sempre e solo in LITRI  (frantoio_log.litri)
--   • GIACENZE   : litri stoccati + kg DERIVATI (colonne generate)
--     I kg NON sono mai scritti a mano: sono GENERATED ALWAYS.
--     Così litri e kg non possono divergere dopo una rettifica.
--   • varieta → qualita (ITALICO / CASALIVA / NP / DOP / BIO)
--   • analisi olio: acidità, perossidi, polifenoli, K232/K270/ΔK, alchil esteri
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── 1. AZIENDE (tenant) ───────────────────────────────────────────────────
CREATE TABLE frantoio_aziende (
  id          BIGSERIAL PRIMARY KEY,
  nome        TEXT NOT NULL,
  ragione_soc TEXT,
  email       TEXT UNIQUE NOT NULL,
  piva        TEXT,
  comune      TEXT,
  provincia   TEXT,
  -- DENSITÀ OLIO: unica costante di conversione L↔kg
  densita     NUMERIC(5,3) NOT NULL DEFAULT 0.916 CHECK (densita > 0),
  attiva      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO frantoio_aziende (id, nome, ragione_soc, email, comune, provincia, densita)
VALUES (1, 'Frantoio Andrea', 'Agririva', 'andrea@agririva.it', 'Mori', 'TN', 0.916);
SELECT setval('frantoio_aziende_id_seq', 1, true);

-- ─── 2. UTENTI ─────────────────────────────────────────────────────────────
CREATE TABLE frantoio_utenti (
  id         BIGSERIAL PRIMARY KEY,
  azienda_id BIGINT NOT NULL REFERENCES frantoio_aziende(id) ON DELETE CASCADE,
  auth_uid   UUID UNIQUE,
  email      TEXT NOT NULL,
  nome       TEXT,
  ruolo      TEXT NOT NULL DEFAULT 'operatore'
             CHECK (ruolo IN ('super_admin','admin','operatore','lettore')),
  attivo     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (azienda_id, email)
);
CREATE INDEX idx_frantoio_utenti_azienda ON frantoio_utenti(azienda_id);
CREATE INDEX idx_frantoio_utenti_auth    ON frantoio_utenti(auth_uid);
INSERT INTO frantoio_utenti (azienda_id, email, nome, ruolo)
VALUES (1, 'andrea@agririva.it', 'Andrea', 'super_admin');

-- ─── 3. QUALITA (ex varietà) ───────────────────────────────────────────────
CREATE TABLE frantoio_qualita (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  azienda_id BIGINT NOT NULL REFERENCES frantoio_aziende(id) ON DELETE CASCADE,
  codice     TEXT NOT NULL,
  nome       TEXT NOT NULL,
  sigla      TEXT NOT NULL,
  bio        BOOLEAN NOT NULL DEFAULT FALSE,
  dop        BOOLEAN NOT NULL DEFAULT FALSE,
  hex        TEXT NOT NULL DEFAULT '#5c7014',
  attiva     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (azienda_id, codice)
);
CREATE INDEX idx_frantoio_qualita_azienda ON frantoio_qualita(azienda_id) WHERE attiva;

INSERT INTO frantoio_qualita (azienda_id, codice, nome, sigla, bio, dop, hex) VALUES
  (1,'ITALICO',        'ITALICO',           'IT',   FALSE, FALSE, '#7a9020'),
  (1,'ITALICO_BIO',    'ITALICO BIO',       'ITB',  TRUE,  FALSE, '#5c7014'),
  (1,'NP',             'NP',                'NP',   FALSE, FALSE, '#a08008'),
  (1,'NP_BIO',         'NP BIO',            'NPB',  TRUE,  FALSE, '#8a7008'),
  (1,'CASALIVA',       'CASALIVA',          'CAS',  FALSE, FALSE, '#3a6818'),
  (1,'CASALIVA_BIO',   'CASALIVA BIO',      'CASB', TRUE,  FALSE, '#2a5010'),
  (1,'DOP',            'DOP',               'DOP',  FALSE, TRUE,  '#1a3878'),
  (1,'DOP_CASALIVA',   'DOP CASALIVA',      'DCAS', FALSE, TRUE,  '#204088'),
  (1,'DOP_CASALIVA_BIO','DOP CASALIVA BIO', 'DCASB',TRUE,  TRUE,  '#182f68');

-- ─── 4. VASCHE — litri stoccati, kg DERIVATI ───────────────────────────────
CREATE TABLE frantoio_vasche (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  azienda_id     BIGINT NOT NULL REFERENCES frantoio_aziende(id) ON DELETE CASCADE,
  numero         INTEGER NOT NULL,
  codice         TEXT NOT NULL,
  nome           TEXT NOT NULL DEFAULT '',
  materiale      TEXT DEFAULT '',        -- BATTENTE | INOX | BIDONE | CUBO | PRIVATI | ...
  posizione      TEXT DEFAULT '',
  capacita_litri NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (capacita_litri >= 0),
  litri          NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (litri >= 0),
  -- KG DERIVATI: mai scrivibili, sempre coerenti con i litri
  capacita_kg    NUMERIC(10,2) GENERATED ALWAYS AS (ROUND(capacita_litri * 0.916, 2)) STORED,
  kg             NUMERIC(10,2) GENERATED ALWAYS AS (ROUND(litri * 0.916, 2)) STORED,
  qualita_id     UUID REFERENCES frantoio_qualita(id) ON DELETE SET NULL,
  campagna       INTEGER,
  note_qualita   TEXT DEFAULT '',
  lotti          JSONB NOT NULL DEFAULT '{}'::JSONB,   -- {codice_lotto: litri}
  attiva         BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (azienda_id, codice),
  UNIQUE (azienda_id, numero)
);
CREATE INDEX idx_frantoio_vasche_azienda ON frantoio_vasche(azienda_id, numero) WHERE attiva;
CREATE INDEX idx_frantoio_vasche_lotti   ON frantoio_vasche USING GIN (lotti);

-- ─── 5. LOTTI ──────────────────────────────────────────────────────────────
CREATE TABLE frantoio_lotti (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  azienda_id     BIGINT NOT NULL REFERENCES frantoio_aziende(id) ON DELETE CASCADE,
  codice         TEXT NOT NULL,
  qualita_id     UUID REFERENCES frantoio_qualita(id) ON DELETE SET NULL,
  campagna       INTEGER,
  data_creazione DATE NOT NULL DEFAULT CURRENT_DATE,
  vasca_origine  TEXT,
  origine        TEXT DEFAULT '',
  conferente     TEXT DEFAULT '',        -- per i vasi "PRIVATI" (olio conto terzi)
  stato          TEXT NOT NULL DEFAULT 'attivo'
                 CHECK (stato IN ('attivo','esaurito','archiviato')),
  note           TEXT DEFAULT '',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (azienda_id, codice)
);
CREATE INDEX idx_frantoio_lotti_azienda ON frantoio_lotti(azienda_id, stato);

-- ─── 6. LOG — MOVIMENTI SEMPRE IN LITRI ────────────────────────────────────
CREATE TABLE frantoio_log (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  azienda_id          BIGINT NOT NULL REFERENCES frantoio_aziende(id) ON DELETE CASCADE,
  ts                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  tipo                TEXT NOT NULL CHECK (tipo IN (
                        'carico','travaso','colmatura','filtrazione',
                        'imbottigliamento','perdita','vendita','riclassifica',
                        'rettifica_carico','rettifica_scarico','rettifica_inventario',
                        'storno','aggiunta')),
  label               TEXT,
  sorgente_codice     TEXT,
  destinazione_codice TEXT,
  -- ⚠ IL MOVIMENTO È IN LITRI. I kg sono derivati, mai inseriti.
  litri               NUMERIC(10,2) CHECK (litri IS NULL OR litri >= 0),
  kg                  NUMERIC(10,2) GENERATED ALWAYS AS (ROUND(litri * 0.916, 2)) STORED,
  qualita_id          UUID REFERENCES frantoio_qualita(id) ON DELETE SET NULL,
  sigla_qualita       TEXT,
  qualita_nome        TEXT,
  campagna            INTEGER,
  lotto               TEXT,
  note                TEXT,
  lotti_sorgente      JSONB,
  lotti_sorgente_dett TEXT,
  rif_log_id          UUID REFERENCES frantoio_log(id),
  dispositivo         TEXT,
  utente_email        TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_frantoio_log_azienda_ts ON frantoio_log(azienda_id, ts DESC);
CREATE INDEX idx_frantoio_log_tipo       ON frantoio_log(azienda_id, tipo);
CREATE INDEX idx_frantoio_log_lotto      ON frantoio_log(azienda_id, lotto) WHERE lotto IS NOT NULL;

-- ─── 7. ANALISI OLIO ───────────────────────────────────────────────────────
CREATE TABLE frantoio_analisi (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  azienda_id    BIGINT NOT NULL REFERENCES frantoio_aziende(id) ON DELETE CASCADE,
  vasca_codice  TEXT,
  lotto         TEXT,
  data          DATE NOT NULL DEFAULT CURRENT_DATE,
  laboratorio   TEXT DEFAULT '',
  -- parametri (unità come da referto: per kg, non per litro)
  acidita        NUMERIC(5,2),   -- % acido oleico    | limite EVO ≤ 0,80
  perossidi      NUMERIC(6,2),   -- meq O2/kg         | limite EVO ≤ 20
  polifenoli     NUMERIC(7,1),   -- mg/kg
  acido_oleico   NUMERIC(5,2),   -- %
  k232           NUMERIC(5,3),   -- limite ≤ 2,50
  k270           NUMERIC(5,3),   -- limite ≤ 0,22
  delta_k        NUMERIC(6,4),   -- limite ≤ 0,01
  alchil_esteri  NUMERIC(6,1),   -- mg/kg | limite ≤ 35
  organolettica  TEXT,
  calcolata      BOOLEAN NOT NULL DEFAULT FALSE,
  note           TEXT DEFAULT '',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_frantoio_analisi_azienda ON frantoio_analisi(azienda_id, data DESC);

-- ─── 8. CONFIG ─────────────────────────────────────────────────────────────
CREATE TABLE frantoio_config (
  id         BIGSERIAL PRIMARY KEY,
  azienda_id BIGINT NOT NULL REFERENCES frantoio_aziende(id) ON DELETE CASCADE,
  chiave     TEXT NOT NULL,
  valore     JSONB,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (azienda_id, chiave)
);

-- ─── 9. HELPER + RLS ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION frantoio_my_azienda_id() RETURNS BIGINT AS $$
  SELECT azienda_id FROM frantoio_utenti WHERE auth_uid = auth.uid() LIMIT 1;
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION frantoio_my_ruolo() RETURNS TEXT AS $$
  SELECT ruolo FROM frantoio_utenti WHERE auth_uid = auth.uid() LIMIT 1;
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION frantoio_is_super() RETURNS BOOLEAN AS $$
  SELECT COALESCE(frantoio_my_ruolo() = 'super_admin', FALSE);
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION frantoio_puo_vedere(p BIGINT) RETURNS BOOLEAN AS $$
  SELECT frantoio_is_super() OR p = frantoio_my_azienda_id();
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION frantoio_puo_scrivere(p BIGINT) RETURNS BOOLEAN AS $$
  SELECT (frantoio_is_super() OR p = frantoio_my_azienda_id())
     AND COALESCE(frantoio_my_ruolo(), '') <> 'lettore';
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

ALTER TABLE frantoio_aziende  ENABLE ROW LEVEL SECURITY;
ALTER TABLE frantoio_utenti   ENABLE ROW LEVEL SECURITY;
ALTER TABLE frantoio_qualita  ENABLE ROW LEVEL SECURITY;
ALTER TABLE frantoio_vasche   ENABLE ROW LEVEL SECURITY;
ALTER TABLE frantoio_lotti    ENABLE ROW LEVEL SECURITY;
ALTER TABLE frantoio_log      ENABLE ROW LEVEL SECURITY;
ALTER TABLE frantoio_analisi  ENABLE ROW LEVEL SECURITY;
ALTER TABLE frantoio_config   ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_f_aziende_sel ON frantoio_aziende FOR SELECT
  USING (frantoio_is_super() OR id = frantoio_my_azienda_id());
CREATE POLICY p_f_aziende_upd ON frantoio_aziende FOR UPDATE
  USING (frantoio_is_super() OR id = frantoio_my_azienda_id())
  WITH CHECK (frantoio_is_super() OR id = frantoio_my_azienda_id());

-- bootstrap primo login (patch v2.2 già incorporata)
CREATE POLICY p_f_utenti_self_sel ON frantoio_utenti FOR SELECT
  USING (email = auth.email() OR frantoio_puo_vedere(azienda_id));
CREATE POLICY p_f_utenti_self_link ON frantoio_utenti FOR UPDATE
  USING (email = auth.email() AND auth_uid IS NULL)
  WITH CHECK (email = auth.email() AND auth_uid = auth.uid());
CREATE POLICY p_f_utenti_admin ON frantoio_utenti FOR ALL
  USING (frantoio_is_super()) WITH CHECK (frantoio_is_super());

CREATE POLICY p_f_qualita_sel ON frantoio_qualita FOR SELECT USING (frantoio_puo_vedere(azienda_id));
CREATE POLICY p_f_qualita_wr  ON frantoio_qualita FOR ALL    USING (frantoio_puo_scrivere(azienda_id)) WITH CHECK (frantoio_puo_scrivere(azienda_id));
CREATE POLICY p_f_vasche_sel  ON frantoio_vasche  FOR SELECT USING (frantoio_puo_vedere(azienda_id));
CREATE POLICY p_f_vasche_wr   ON frantoio_vasche  FOR ALL    USING (frantoio_puo_scrivere(azienda_id)) WITH CHECK (frantoio_puo_scrivere(azienda_id));
CREATE POLICY p_f_lotti_sel   ON frantoio_lotti   FOR SELECT USING (frantoio_puo_vedere(azienda_id));
CREATE POLICY p_f_lotti_wr    ON frantoio_lotti   FOR ALL    USING (frantoio_puo_scrivere(azienda_id)) WITH CHECK (frantoio_puo_scrivere(azienda_id));
CREATE POLICY p_f_log_sel     ON frantoio_log     FOR SELECT USING (frantoio_puo_vedere(azienda_id));
CREATE POLICY p_f_log_ins     ON frantoio_log     FOR INSERT WITH CHECK (frantoio_puo_scrivere(azienda_id));
CREATE POLICY p_f_analisi_sel ON frantoio_analisi FOR SELECT USING (frantoio_puo_vedere(azienda_id));
CREATE POLICY p_f_analisi_wr  ON frantoio_analisi FOR ALL    USING (frantoio_puo_scrivere(azienda_id)) WITH CHECK (frantoio_puo_scrivere(azienda_id));
CREATE POLICY p_f_config_sel  ON frantoio_config  FOR SELECT USING (frantoio_puo_vedere(azienda_id));
CREATE POLICY p_f_config_wr   ON frantoio_config  FOR ALL    USING (frantoio_puo_scrivere(azienda_id)) WITH CHECK (frantoio_puo_scrivere(azienda_id));

-- ─── 10. SEED VASCHE (88, da DATI_BASE_FRANTOIO.XLSX) ──────────────────────
INSERT INTO frantoio_vasche (azienda_id, numero, codice, materiale, capacita_litri) VALUES
  (1, 1, '1', 'BATTENTE', 1000.0),
  (1, 2, '2', 'BATTENTE', 1000.0),
  (1, 3, '3', 'BATTENTE', 1000.0),
  (1, 4, '6', 'BATTENTE', 2000.0),
  (1, 5, '7', 'BATTENTE', 2000.0),
  (1, 6, '9', 'BATTENTE', 3000.0),
  (1, 7, '10', 'BATTENTE', 3000.0),
  (1, 8, '11', 'BATTENTE', 3000.0),
  (1, 9, '12', 'BATTENTE', 1000.0),
  (1, 10, '13', 'BATTENTE', 1000.0),
  (1, 11, '14', 'BATTENTE', 1000.0),
  (1, 12, '15', 'BATTENTE', 1500.0),
  (1, 13, '16', 'BATTENTE', 1500.0),
  (1, 14, '17', 'BATTENTE', 1500.0),
  (1, 15, '18', 'BATTENTE', 5000.0),
  (1, 16, '19', 'BATTENTE', 5000.0),
  (1, 17, '20', 'BATTENTE', 4500.0),
  (1, 18, '21', 'BATTENTE', 4500.0),
  (1, 19, '22', 'BATTENTE', 513.1),
  (1, 20, '23', 'BATTENTE', 513.1),
  (1, 21, '24', 'BATTENTE', 320.96),
  (1, 22, '25', 'BATTENTE', 320.96),
  (1, 23, '26', 'BATTENTE', 4500.0),
  (1, 24, '27', 'BATTENTE', 4500.0),
  (1, 25, '30', 'INOX', 50.0),
  (1, 26, '31', 'INOX', 50.0),
  (1, 27, '32', 'INOX', 50.0),
  (1, 28, '50', 'BIDONE', 289.3),
  (1, 29, '51', 'BIDONE', 289.3),
  (1, 30, '52', 'BIDONE', 289.3),
  (1, 31, '53', 'BIDONE', 289.3),
  (1, 32, '54', 'BIDONE', 289.3),
  (1, 33, '55', 'BIDONE', 175.0),
  (1, 34, '56', 'BIDONE', 175.0),
  (1, 35, '57', 'BIDONE', 175.0),
  (1, 36, '58', 'BIDONE', 175.0),
  (1, 37, '59', 'BIDONE', 175.0),
  (1, 38, '60', 'BIDONE', 175.0),
  (1, 39, '61', 'BIDONE', 175.0),
  (1, 40, '62', 'BIDONE', 175.0),
  (1, 41, '63', 'BIDONE', 175.0),
  (1, 42, '64', 'BIDONE', 175.0),
  (1, 43, '65', 'BIDONE', 175.0),
  (1, 44, '66', 'BIDONE', 344.0),
  (1, 45, '67', 'BIDONE', 344.0),
  (1, 46, '68', 'BIDONE', 344.0),
  (1, 47, '69', 'BIDONE', 344.0),
  (1, 48, '70', 'BIDONE', 344.0),
  (1, 49, '71', 'CUBO', 1050.22),
  (1, 50, '72', 'CUBO', 1050.22),
  (1, 51, '73', 'CUBO', 1050.22),
  (1, 52, '74', 'CUBO', 1050.22),
  (1, 53, '75', 'CUBO', 1050.22),
  (1, 54, '76', 'CUBO', 1050.22),
  (1, 55, '77', 'CUBO', 1050.22),
  (1, 56, '78', 'CUBO', 1050.22),
  (1, 57, '79', 'CUBO', 1050.22),
  (1, 58, '80', 'CUBO', 1050.22),
  (1, 59, '81', 'CUBO', 1050.22),
  (1, 60, '82', 'CUBO', 1050.22),
  (1, 61, '83', 'CUBO', 1050.22),
  (1, 62, '84', 'CUBO', 1050.22),
  (1, 63, '85', 'CUBO', 1050.22),
  (1, 64, '86', 'CUBO', 1050.22),
  (1, 65, '1R', 'BATTENTE', 2000.0),
  (1, 66, 'A', 'BATTENTE', 2000.0),
  (1, 67, 'B', 'BATTENTE', 2000.0),
  (1, 68, 'C1', 'BATTENTE', 1000.0),
  (1, 69, 'C2', 'NO BATTENTE', 800.0),
  (1, 70, 'G', 'SEMPREPIENO', 300.0),
  (1, 71, 'P01', 'PRIVATI', 200.0),
  (1, 72, 'P02', 'PRIVATI', 200.0),
  (1, 73, 'P03', 'PRIVATI', 200.0),
  (1, 74, 'P04', 'PRIVATI', 200.0),
  (1, 75, 'P05', 'PRIVATI', 200.0),
  (1, 76, 'P06', 'PRIVATI', 200.0),
  (1, 77, 'P07', 'PRIVATI', 200.0),
  (1, 78, 'P08', 'PRIVATI', 200.0),
  (1, 79, 'P09', 'PRIVATI', 100.0),
  (1, 80, 'P10', 'PRIVATI', 100.0),
  (1, 81, 'P11', 'PRIVATI', 100.0),
  (1, 82, 'P12', 'PRIVATI', 100.0),
  (1, 83, 'P13', 'PRIVATI', 100.0),
  (1, 84, 'P14', 'PRIVATI', 100.0),
  (1, 85, 'P15', 'PRIVATI', 100.0),
  (1, 86, 'P16', 'PRIVATI', 100.0),
  (1, 87, 'PXX', 'PRIVATI', 100.0),
  (1, 88, 'CIST COMAI', 'PRIVATI', 500.0);

-- ═══════════════════════════════════════════════════════════════════════════
--  FINE SCHEMA v1.0
-- ═══════════════════════════════════════════════════════════════════════════
