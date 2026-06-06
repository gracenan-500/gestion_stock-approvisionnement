
--  SYSTÈME DE GESTION DE STOCK — PostgreSQL
--  Basé sur le cahier des charges manuscrit
--  4 Modules : Approvisionnements | Ventes | Structure | Sécurité
--  + Journal d'audit + Corbeille (archivage XML + restauration)
-- ================================================================

BEGIN;

-- ================================================================
-- EXTENSION
-- ================================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ================================================================
-- MODULE 3 — STRUCTURE GLOBALE DU SYSTÈME
-- ================================================================

-- 3.1 Famille de produits
CREATE TABLE famille_produit (
    id_famille   SERIAL        PRIMARY KEY,
    libelle      VARCHAR(100)  NOT NULL UNIQUE,
    description  TEXT,
    created_at   TIMESTAMP     NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMP     NOT NULL DEFAULT NOW(),
    deleted_at   TIMESTAMP     -- soft delete (corbeille)
);

-- 3.2 Produit (avec auto-référence produit père / produit fils)
CREATE TABLE produit (
    id_produit        SERIAL         PRIMARY KEY,
    id_famille        INTEGER        NOT NULL
                      REFERENCES famille_produit(id_famille)
                      ON DELETE CASCADE,
    id_produit_pere   INTEGER        -- produit fils d'un père
                      REFERENCES produit(id_produit)
                      ON DELETE CASCADE,
    code              VARCHAR(50)    NOT NULL UNIQUE,
    designation       VARCHAR(200)   NOT NULL,
    unite             VARCHAR(30)    NOT NULL DEFAULT 'unité',
    prix_achat        NUMERIC(15,2)  NOT NULL DEFAULT 0,
    prix_vente        NUMERIC(15,2)  NOT NULL DEFAULT 0,
    stock_actuel      INTEGER        NOT NULL DEFAULT 0,
    stock_alerte      INTEGER        NOT NULL DEFAULT 0,
    is_fractionnaire  BOOLEAN        NOT NULL DEFAULT FALSE,
    facteur_fraction  NUMERIC(10,4)  DEFAULT 1,
    created_at        TIMESTAMP      NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMP      NOT NULL DEFAULT NOW(),
    deleted_at        TIMESTAMP,
    CONSTRAINT chk_prix_achat  CHECK (prix_achat  >= 0),
    CONSTRAINT chk_prix_vente  CHECK (prix_vente  >= 0),
    CONSTRAINT chk_stock_alerte CHECK (stock_alerte >= 0)
);

-- 3.3 Fournisseurs
CREATE TABLE fournisseur (
    id_fournisseur SERIAL        PRIMARY KEY,
    nom            VARCHAR(150)  NOT NULL,
    telephone      VARCHAR(30),
    email          VARCHAR(100),
    adresse        TEXT,
    created_at     TIMESTAMP     NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMP     NOT NULL DEFAULT NOW(),
    deleted_at     TIMESTAMP
);

-- 3.4 Catégories clients
CREATE TABLE categorie_client (
    id_categorie SERIAL        PRIMARY KEY,
    libelle      VARCHAR(100)  NOT NULL UNIQUE,
    remise_pct   NUMERIC(5,2)  NOT NULL DEFAULT 0
                 CHECK (remise_pct BETWEEN 0 AND 100)
);

-- 3.5 Clients
CREATE TABLE client (
    id_client    SERIAL        PRIMARY KEY,
    id_categorie INTEGER       NOT NULL
                 REFERENCES categorie_client(id_categorie)
                 ON DELETE RESTRICT,
    nom          VARCHAR(150)  NOT NULL,
    telephone    VARCHAR(30),
    email        VARCHAR(100),
    adresse      TEXT,
    created_at   TIMESTAMP     NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMP     NOT NULL DEFAULT NOW(),
    deleted_at   TIMESTAMP
);

-- 3.6 Banques
CREATE TABLE banque (
    id_banque      SERIAL        PRIMARY KEY,
    nom            VARCHAR(150)  NOT NULL,
    numero_compte  VARCHAR(50),
    adresse        TEXT,
    created_at     TIMESTAMP     NOT NULL DEFAULT NOW()
);

-- 3.7 Versements en banque par période
CREATE TABLE versement_banque (
    id_versement   SERIAL         PRIMARY KEY,
    id_banque      INTEGER        NOT NULL
                   REFERENCES banque(id_banque)
                   ON DELETE RESTRICT,
    montant        NUMERIC(15,2)  NOT NULL CHECK (montant > 0),
    date_versement DATE           NOT NULL DEFAULT CURRENT_DATE,
    reference      TEXT,
    created_at     TIMESTAMP      NOT NULL DEFAULT NOW()
);

-- ================================================================
-- MODULE 4 — SÉCURITÉ (Gestion des utilisateurs et comptes)
-- ================================================================

-- 4.1 Groupes d'utilisateurs
CREATE TABLE groupe_utilisateur (
    id_groupe   SERIAL        PRIMARY KEY,
    libelle     VARCHAR(100)  NOT NULL UNIQUE,
    description TEXT,
    created_at  TIMESTAMP     NOT NULL DEFAULT NOW(),
    deleted_at  TIMESTAMP
);

-- 4.2 Droits affectés à un groupe (par module et action)
CREATE TABLE droit (
    id_droit  SERIAL       PRIMARY KEY,
    id_groupe INTEGER      NOT NULL
              REFERENCES groupe_utilisateur(id_groupe)
              ON DELETE CASCADE,
    module    VARCHAR(80)  NOT NULL
              CHECK (module IN (
                'approvisionnement','vente',
                'structure','securite'
              )),
    action    VARCHAR(80)  NOT NULL
              CHECK (action IN (
                'creer','modifier','supprimer',
                'imprimer','consulter','regler'
              )),
    autorise  BOOLEAN      NOT NULL DEFAULT FALSE,
    UNIQUE (id_groupe, module, action)
);

-- 4.3 Utilisateurs (affectés à un groupe)
CREATE TABLE utilisateur (
    id_utilisateur SERIAL        PRIMARY KEY,
    id_groupe      INTEGER       NOT NULL
                   REFERENCES groupe_utilisateur(id_groupe)
                   ON DELETE RESTRICT,
    nom            VARCHAR(80)   NOT NULL,
    prenom         VARCHAR(80),
    login          VARCHAR(50)   NOT NULL UNIQUE,
    password_hash  TEXT          NOT NULL,
    actif          BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMP     NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMP     NOT NULL DEFAULT NOW(),
    deleted_at     TIMESTAMP
);

-- Hachage automatique du mot de passe (bcrypt via pgcrypto)
CREATE OR REPLACE FUNCTION trg_hash_password()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.password_hash NOT LIKE '$2a$%' THEN
        NEW.password_hash := crypt(NEW.password_hash,
                                   gen_salt('bf', 12));
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_pwd_utilisateur
BEFORE INSERT OR UPDATE OF password_hash ON utilisateur
FOR EACH ROW EXECUTE FUNCTION trg_hash_password();

-- ================================================================
-- MODULE 1 — GESTION DES APPROVISIONNEMENTS
-- ================================================================

-- 1.1 Commande fournisseur (Éditer bon de commande fournisseur)
CREATE TABLE commande_fournisseur (
    id_commande_f  SERIAL         PRIMARY KEY,
    id_fournisseur INTEGER        NOT NULL
                   REFERENCES fournisseur(id_fournisseur)
                   ON DELETE CASCADE,
    id_utilisateur INTEGER        NOT NULL
                   REFERENCES utilisateur(id_utilisateur)
                   ON DELETE RESTRICT,
    numero_bc      VARCHAR(50)    NOT NULL UNIQUE,  -- numéro du bon de commande
    date_commande  DATE           NOT NULL DEFAULT CURRENT_DATE,
    statut         VARCHAR(30)    NOT NULL DEFAULT 'en_attente'
                   CHECK (statut IN (
                     'en_attente','validee','recue','annulee'
                   )),
    montant_total  NUMERIC(15,2)  NOT NULL DEFAULT 0,
    observations   TEXT,
    created_at     TIMESTAMP      NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMP      NOT NULL DEFAULT NOW(),
    deleted_at     TIMESTAMP      -- corbeille
);

CREATE TABLE ligne_commande_f (
    id_ligne_f     SERIAL         PRIMARY KEY,
    id_commande_f  INTEGER        NOT NULL
                   REFERENCES commande_fournisseur(id_commande_f)
                   ON DELETE CASCADE,
    id_produit     INTEGER        NOT NULL
                   REFERENCES produit(id_produit)
                   ON DELETE CASCADE,
    quantite       INTEGER        NOT NULL CHECK (quantite > 0),
    prix_unitaire  NUMERIC(15,2)  NOT NULL CHECK (prix_unitaire >= 0),
    montant_ligne  NUMERIC(15,2)
                   GENERATED ALWAYS AS (quantite * prix_unitaire) STORED
);

-- 1.2 Bon de réception (Réceptionner les produits)
CREATE TABLE bon_reception (
    id_reception   SERIAL     PRIMARY KEY,
    id_commande_f  INTEGER    NOT NULL
                   REFERENCES commande_fournisseur(id_commande_f)
                   ON DELETE CASCADE,
    id_utilisateur INTEGER    NOT NULL
                   REFERENCES utilisateur(id_utilisateur)
                   ON DELETE RESTRICT,
    numero_br      VARCHAR(50) NOT NULL UNIQUE,
    date_reception DATE        NOT NULL DEFAULT CURRENT_DATE,
    observations   TEXT,
    created_at     TIMESTAMP   NOT NULL DEFAULT NOW()
);

CREATE TABLE ligne_reception (
    id_ligne_r     SERIAL         PRIMARY KEY,
    id_reception   INTEGER        NOT NULL
                   REFERENCES bon_reception(id_reception)
                   ON DELETE CASCADE,
    id_produit     INTEGER        NOT NULL
                   REFERENCES produit(id_produit)
                   ON DELETE CASCADE,
    quantite_recue INTEGER        NOT NULL CHECK (quantite_recue > 0),
    prix_unitaire  NUMERIC(15,2)  NOT NULL CHECK (prix_unitaire >= 0)
);

-- 1.3 Facture fournisseur + règlement (Régler la facture du fournisseur)
CREATE TABLE facture_fournisseur (
    id_facture_f     SERIAL         PRIMARY KEY,
    id_commande_f    INTEGER        NOT NULL
                     REFERENCES commande_fournisseur(id_commande_f)
                     ON DELETE CASCADE,
    numero_facture   VARCHAR(50)    NOT NULL UNIQUE,
    date_facture     DATE           NOT NULL DEFAULT CURRENT_DATE,
    montant_ht       NUMERIC(15,2)  NOT NULL CHECK (montant_ht >= 0),
    taux_tva         NUMERIC(5,2)   NOT NULL DEFAULT 0,
    montant_tva      NUMERIC(15,2)
                     GENERATED ALWAYS AS (montant_ht * taux_tva / 100) STORED,
    montant_ttc      NUMERIC(15,2)  NOT NULL,
    statut_paiement  VARCHAR(20)    NOT NULL DEFAULT 'impayee'
                     CHECK (statut_paiement IN ('impayee','partielle','soldee')),
    created_at       TIMESTAMP      NOT NULL DEFAULT NOW()
);

CREATE TABLE reglement_fournisseur (
    id_reglement_f SERIAL         PRIMARY KEY,
    id_facture_f   INTEGER        NOT NULL
                   REFERENCES facture_fournisseur(id_facture_f)
                   ON DELETE CASCADE,
    id_banque      INTEGER
                   REFERENCES banque(id_banque)
                   ON DELETE RESTRICT,
    date_reglement DATE           NOT NULL DEFAULT CURRENT_DATE,
    montant        NUMERIC(15,2)  NOT NULL CHECK (montant > 0),
    mode_paiement  VARCHAR(30)    NOT NULL DEFAULT 'especes'
                   CHECK (mode_paiement IN (
                     'especes','cheque','virement','mobile_money'
                   )),
    reference      TEXT,
    created_at     TIMESTAMP      NOT NULL DEFAULT NOW()
);

-- 1.4 Entrée produits issus de dons (bon d'entrée)
CREATE TABLE don (
    id_don         SERIAL      PRIMARY KEY,
    id_fournisseur INTEGER
                   REFERENCES fournisseur(id_fournisseur)
                   ON DELETE SET NULL,
    id_utilisateur INTEGER     NOT NULL
                   REFERENCES utilisateur(id_utilisateur)
                   ON DELETE RESTRICT,
    numero_bon     VARCHAR(50) NOT NULL UNIQUE,  -- bon d'entrée
    date_don       DATE        NOT NULL DEFAULT CURRENT_DATE,
    description    TEXT,
    created_at     TIMESTAMP   NOT NULL DEFAULT NOW()
);

CREATE TABLE ligne_don (
    id_ligne_d      SERIAL         PRIMARY KEY,
    id_don          INTEGER        NOT NULL
                    REFERENCES don(id_don)
                    ON DELETE CASCADE,
    id_produit      INTEGER        NOT NULL
                    REFERENCES produit(id_produit)
                    ON DELETE CASCADE,
    quantite        INTEGER        NOT NULL CHECK (quantite > 0),
    valeur_unitaire NUMERIC(15,2)  NOT NULL DEFAULT 0
);

-- ================================================================
-- MODULE 2 — GESTION DES VENTES
-- ================================================================

-- 2.1 Commande client (passer commande client)
CREATE TABLE commande_client (
    id_commande_c  SERIAL         PRIMARY KEY,
    id_client      INTEGER        NOT NULL
                   REFERENCES client(id_client)
                   ON DELETE CASCADE,
    id_utilisateur INTEGER        NOT NULL
                   REFERENCES utilisateur(id_utilisateur)
                   ON DELETE RESTRICT,
    numero_bc      VARCHAR(50)    NOT NULL UNIQUE,
    date_commande  DATE           NOT NULL DEFAULT CURRENT_DATE,
    statut         VARCHAR(30)    NOT NULL DEFAULT 'en_attente'
                   CHECK (statut IN (
                     'en_attente','validee','livree','annulee'
                   )),
    montant_total  NUMERIC(15,2)  NOT NULL DEFAULT 0,
    -- vente au comptant : caissier → client occasionnel sans bon de commande
    est_comptant   BOOLEAN        NOT NULL DEFAULT FALSE,
    observations   TEXT,
    created_at     TIMESTAMP      NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMP      NOT NULL DEFAULT NOW(),
    deleted_at     TIMESTAMP
);

CREATE TABLE ligne_commande_c (
    id_ligne_c     SERIAL         PRIMARY KEY,
    id_commande_c  INTEGER        NOT NULL
                   REFERENCES commande_client(id_commande_c)
                   ON DELETE CASCADE,
    id_produit     INTEGER        NOT NULL
                   REFERENCES produit(id_produit)
                   ON DELETE CASCADE,
    quantite       INTEGER        NOT NULL CHECK (quantite > 0),
    prix_unitaire  NUMERIC(15,2)  NOT NULL CHECK (prix_unitaire >= 0),
    remise_pct     NUMERIC(5,2)   NOT NULL DEFAULT 0
                   CHECK (remise_pct BETWEEN 0 AND 100),
    montant_ligne  NUMERIC(15,2)
                   GENERATED ALWAYS AS (
                     quantite * prix_unitaire * (1 - remise_pct / 100)
                   ) STORED
);

-- 2.2 Bon de livraison (livrer les produits)
CREATE TABLE bon_livraison (
    id_livraison   SERIAL      PRIMARY KEY,
    id_commande_c  INTEGER     NOT NULL
                   REFERENCES commande_client(id_commande_c)
                   ON DELETE CASCADE,
    id_utilisateur INTEGER     NOT NULL
                   REFERENCES utilisateur(id_utilisateur)
                   ON DELETE RESTRICT,
    numero_bl      VARCHAR(50) NOT NULL UNIQUE,
    date_livraison DATE        NOT NULL DEFAULT CURRENT_DATE,
    observations   TEXT,
    created_at     TIMESTAMP   NOT NULL DEFAULT NOW()
);

CREATE TABLE ligne_livraison (
    id_ligne_l      SERIAL         PRIMARY KEY,
    id_livraison    INTEGER        NOT NULL
                    REFERENCES bon_livraison(id_livraison)
                    ON DELETE CASCADE,
    id_produit      INTEGER        NOT NULL
                    REFERENCES produit(id_produit)
                    ON DELETE CASCADE,
    quantite_livree INTEGER        NOT NULL CHECK (quantite_livree > 0),
    prix_unitaire   NUMERIC(15,2)  NOT NULL CHECK (prix_unitaire >= 0)
);

-- 2.3 Facture client + règlement (régler facture client)
CREATE TABLE facture_client (
    id_facture_c     SERIAL         PRIMARY KEY,
    id_commande_c    INTEGER        NOT NULL
                     REFERENCES commande_client(id_commande_c)
                     ON DELETE CASCADE,
    numero_facture   VARCHAR(50)    NOT NULL UNIQUE,
    date_facture     DATE           NOT NULL DEFAULT CURRENT_DATE,
    montant_ht       NUMERIC(15,2)  NOT NULL CHECK (montant_ht >= 0),
    taux_tva         NUMERIC(5,2)   NOT NULL DEFAULT 0,
    montant_tva      NUMERIC(15,2)
                     GENERATED ALWAYS AS (montant_ht * taux_tva / 100) STORED,
    montant_ttc      NUMERIC(15,2)  NOT NULL,
    statut_paiement  VARCHAR(20)    NOT NULL DEFAULT 'impayee'
                     CHECK (statut_paiement IN ('impayee','partielle','soldee')),
    created_at       TIMESTAMP      NOT NULL DEFAULT NOW()
);

CREATE TABLE reglement_client (
    id_reglement_c SERIAL         PRIMARY KEY,
    id_facture_c   INTEGER        NOT NULL
                   REFERENCES facture_client(id_facture_c)
                   ON DELETE CASCADE,
    id_banque      INTEGER
                   REFERENCES banque(id_banque)
                   ON DELETE RESTRICT,
    date_reglement DATE           NOT NULL DEFAULT CURRENT_DATE,
    montant        NUMERIC(15,2)  NOT NULL CHECK (montant > 0),
    mode_paiement  VARCHAR(30)    NOT NULL DEFAULT 'especes'
                   CHECK (mode_paiement IN (
                     'especes','cheque','virement','mobile_money'
                   )),
    reference      TEXT,
    created_at     TIMESTAMP      NOT NULL DEFAULT NOW()
);

-- 2.4 Bon de sortie produit
-- (produit périmé, cassé, etc. — PAS une vente, PAS une facture)
CREATE TABLE bon_sortie (
    id_sortie      SERIAL      PRIMARY KEY,
    id_utilisateur INTEGER     NOT NULL
                   REFERENCES utilisateur(id_utilisateur)
                   ON DELETE RESTRICT,
    numero_bs      VARCHAR(50) NOT NULL UNIQUE,
    date_sortie    DATE        NOT NULL DEFAULT CURRENT_DATE,
    motif          VARCHAR(50) NOT NULL
                   CHECK (motif IN (
                     'perime','casse','perte','offert','autre'
                   )),
    observations   TEXT,
    created_at     TIMESTAMP   NOT NULL DEFAULT NOW()
);

CREATE TABLE ligne_sortie (
    id_ligne_s      SERIAL         PRIMARY KEY,
    id_sortie       INTEGER        NOT NULL
                    REFERENCES bon_sortie(id_sortie)
                    ON DELETE CASCADE,
    id_produit      INTEGER        NOT NULL
                    REFERENCES produit(id_produit)
                    ON DELETE CASCADE,
    quantite        INTEGER        NOT NULL CHECK (quantite > 0),
    valeur_unitaire NUMERIC(15,2)  NOT NULL DEFAULT 0,
    motif_detail    TEXT
);

-- ================================================================
-- MODULE AJOUT — JOURNAL D'AUDIT + CORBEILLE (archivage XML)
-- ================================================================

-- Journal d'audit (traçabilité de toutes les actions)
CREATE TABLE journal_audit (
    id_journal       SERIAL      PRIMARY KEY,
    id_utilisateur   INTEGER
                     REFERENCES utilisateur(id_utilisateur)
                     ON DELETE SET NULL,
    table_cible      VARCHAR(80) NOT NULL,
    action           VARCHAR(20) NOT NULL
                     CHECK (action IN (
                       'INSERT','UPDATE','DELETE',
                       'CONNEXION','DECONNEXION','IMPRESSION'
                     )),
    id_enregistrement INTEGER,
    anciennes_valeurs JSONB,       -- valeurs avant modification
    nouvelles_valeurs JSONB,       -- valeurs après modification
    ip_adresse        INET,
    created_at        TIMESTAMP   NOT NULL DEFAULT NOW()
);

-- Corbeille / Archivage XML (suppression + restauration)
-- Conforme à la spécification : XML conserve l'objet + ses dépendants
CREATE TABLE archive_xml (
    id_archive     SERIAL       PRIMARY KEY,
    entite         VARCHAR(80)  NOT NULL,   -- nom de la table
    id_entite      INTEGER      NOT NULL,   -- id de l'enregistrement
    xml_data       TEXT         NOT NULL,   -- objet sérialisé + enfants
    action         VARCHAR(20)  NOT NULL
                   CHECK (action IN ('suppression','restauration')),
    id_utilisateur INTEGER
                   REFERENCES utilisateur(id_utilisateur)
                   ON DELETE SET NULL,
    created_at     TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_archive_entite ON archive_xml(entite, id_entite);

-- ================================================================
-- INDEX DE PERFORMANCE
-- ================================================================

CREATE INDEX idx_produit_famille    ON produit(id_famille)      WHERE deleted_at IS NULL;
CREATE INDEX idx_produit_pere       ON produit(id_produit_pere);
CREATE INDEX idx_produit_deleted    ON produit(deleted_at)       WHERE deleted_at IS NULL;
CREATE INDEX idx_client_categorie   ON client(id_categorie)      WHERE deleted_at IS NULL;
CREATE INDEX idx_fournisseur_del    ON fournisseur(deleted_at)   WHERE deleted_at IS NULL;
CREATE INDEX idx_cf_date            ON commande_fournisseur(date_commande) WHERE deleted_at IS NULL;
CREATE INDEX idx_cf_statut          ON commande_fournisseur(statut)        WHERE deleted_at IS NULL;
CREATE INDEX idx_cc_date            ON commande_client(date_commande)      WHERE deleted_at IS NULL;
CREATE INDEX idx_cc_statut          ON commande_client(statut)             WHERE deleted_at IS NULL;
CREATE INDEX idx_cc_comptant        ON commande_client(est_comptant)       WHERE est_comptant = TRUE;
CREATE INDEX idx_utilisateur_login  ON utilisateur(login)        WHERE deleted_at IS NULL;
CREATE INDEX idx_journal_date       ON journal_audit(created_at);
CREATE INDEX idx_journal_table      ON journal_audit(table_cible, action);

-- ================================================================
-- TRIGGERS — MOUVEMENTS DE STOCK AUTOMATIQUES
-- ================================================================

-- Incrément stock sur réception
CREATE OR REPLACE FUNCTION trg_stock_reception()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    UPDATE produit
    SET stock_actuel = stock_actuel + NEW.quantite_recue,
        updated_at   = NOW()
    WHERE id_produit = NEW.id_produit;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_reception_stock
AFTER INSERT ON ligne_reception
FOR EACH ROW EXECUTE FUNCTION trg_stock_reception();

-- Incrément stock sur don
CREATE OR REPLACE FUNCTION trg_stock_don()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    UPDATE produit
    SET stock_actuel = stock_actuel + NEW.quantite,
        updated_at   = NOW()
    WHERE id_produit = NEW.id_produit;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_don_stock
AFTER INSERT ON ligne_don
FOR EACH ROW EXECUTE FUNCTION trg_stock_don();

-- Décrémentation stock sur livraison (avec vérification)
CREATE OR REPLACE FUNCTION trg_stock_livraison()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_stock INTEGER;
BEGIN
    SELECT stock_actuel INTO v_stock
    FROM produit WHERE id_produit = NEW.id_produit;

    IF v_stock < NEW.quantite_livree THEN
        RAISE EXCEPTION
          'Stock insuffisant pour le produit % : % disponible, % demandé.',
          NEW.id_produit, v_stock, NEW.quantite_livree;
    END IF;

    UPDATE produit
    SET stock_actuel = stock_actuel - NEW.quantite_livree,
        updated_at   = NOW()
    WHERE id_produit = NEW.id_produit;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_livraison_stock
BEFORE INSERT ON ligne_livraison
FOR EACH ROW EXECUTE FUNCTION trg_stock_livraison();

-- Décrémentation stock sur bon de sortie
CREATE OR REPLACE FUNCTION trg_stock_sortie()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    UPDATE produit
    SET stock_actuel = stock_actuel - NEW.quantite,
        updated_at   = NOW()
    WHERE id_produit = NEW.id_produit;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_sortie_stock
AFTER INSERT ON ligne_sortie
FOR EACH ROW EXECUTE FUNCTION trg_stock_sortie();

-- ================================================================
-- TRIGGERS — RECALCUL AUTOMATIQUE DU MONTANT TOTAL
-- ================================================================

-- Recalcul montant total commande fournisseur
CREATE OR REPLACE FUNCTION trg_total_cf()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    UPDATE commande_fournisseur
    SET montant_total = (
        SELECT COALESCE(SUM(montant_ligne), 0)
        FROM ligne_commande_f
        WHERE id_commande_f = COALESCE(NEW.id_commande_f, OLD.id_commande_f)
    ), updated_at = NOW()
    WHERE id_commande_f = COALESCE(NEW.id_commande_f, OLD.id_commande_f);
    RETURN NULL;
END;
$$;
CREATE TRIGGER trg_total_commande_f
AFTER INSERT OR UPDATE OR DELETE ON ligne_commande_f
FOR EACH ROW EXECUTE FUNCTION trg_total_cf();

-- Recalcul montant total commande client
CREATE OR REPLACE FUNCTION trg_total_cc()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    UPDATE commande_client
    SET montant_total = (
        SELECT COALESCE(SUM(montant_ligne), 0)
        FROM ligne_commande_c
        WHERE id_commande_c = COALESCE(NEW.id_commande_c, OLD.id_commande_c)
    ), updated_at = NOW()
    WHERE id_commande_c = COALESCE(NEW.id_commande_c, OLD.id_commande_c);
    RETURN NULL;
END;
$$;
CREATE TRIGGER trg_total_commande_c
AFTER INSERT OR UPDATE OR DELETE ON ligne_commande_c
FOR EACH ROW EXECUTE FUNCTION trg_total_cc();

-- ================================================================
-- TRIGGERS — ARCHIVAGE XML (corbeille + restauration)
-- ================================================================

-- Archivage commande fournisseur lors du soft delete
CREATE OR REPLACE FUNCTION trg_archive_cf()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_xml TEXT;
BEGIN
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
        SELECT xmlelement(name commande_fournisseur,
            xmlforest(
                NEW.id_commande_f  AS id,
                NEW.id_fournisseur AS fournisseur,
                NEW.numero_bc      AS numero_bc,
                NEW.date_commande  AS date_commande,
                NEW.statut         AS statut,
                NEW.montant_total  AS montant_total
            ),
            (SELECT xmlagg(xmlelement(name ligne,
                xmlforest(
                    l.id_produit    AS produit,
                    l.quantite      AS quantite,
                    l.prix_unitaire AS pu,
                    l.montant_ligne AS montant
                )
            )) FROM ligne_commande_f l
               WHERE l.id_commande_f = NEW.id_commande_f)
        )::TEXT INTO v_xml;

        INSERT INTO archive_xml(entite, id_entite, xml_data, action)
        VALUES ('commande_fournisseur', NEW.id_commande_f, v_xml, 'suppression');
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_archive_commande_f
AFTER UPDATE ON commande_fournisseur
FOR EACH ROW EXECUTE FUNCTION trg_archive_cf();

-- Archivage commande client lors du soft delete
CREATE OR REPLACE FUNCTION trg_archive_cc()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_xml TEXT;
BEGIN
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
        SELECT xmlelement(name commande_client,
            xmlforest(
                NEW.id_commande_c AS id,
                NEW.id_client     AS client,
                NEW.numero_bc     AS numero_bc,
                NEW.date_commande AS date_commande,
                NEW.statut        AS statut,
                NEW.montant_total AS montant_total,
                NEW.est_comptant  AS comptant
            ),
            (SELECT xmlagg(xmlelement(name ligne,
                xmlforest(
                    l.id_produit    AS produit,
                    l.quantite      AS quantite,
                    l.prix_unitaire AS pu,
                    l.remise_pct    AS remise,
                    l.montant_ligne AS montant
                )
            )) FROM ligne_commande_c l
               WHERE l.id_commande_c = NEW.id_commande_c)
        )::TEXT INTO v_xml;

        INSERT INTO archive_xml(entite, id_entite, xml_data, action)
        VALUES ('commande_client', NEW.id_commande_c, v_xml, 'suppression');
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_archive_commande_c
AFTER UPDATE ON commande_client
FOR EACH ROW EXECUTE FUNCTION trg_archive_cc();

-- Archivage fournisseur
CREATE OR REPLACE FUNCTION trg_archive_fournisseur()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
        INSERT INTO archive_xml(entite, id_entite, xml_data, action)
        VALUES ('fournisseur', NEW.id_fournisseur, row_to_json(NEW)::TEXT, 'suppression');
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_archive_fourn
AFTER UPDATE ON fournisseur
FOR EACH ROW EXECUTE FUNCTION trg_archive_fournisseur();

-- Archivage client
CREATE OR REPLACE FUNCTION trg_archive_client()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
        INSERT INTO archive_xml(entite, id_entite, xml_data, action)
        VALUES ('client', NEW.id_client, row_to_json(NEW)::TEXT, 'suppression');
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_archive_cli
AFTER UPDATE ON client
FOR EACH ROW EXECUTE FUNCTION trg_archive_client();

-- Archivage produit
CREATE OR REPLACE FUNCTION trg_archive_produit()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
        INSERT INTO archive_xml(entite, id_entite, xml_data, action)
        VALUES ('produit', NEW.id_produit, row_to_json(NEW)::TEXT, 'suppression');
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_archive_prod
AFTER UPDATE ON produit
FOR EACH ROW EXECUTE FUNCTION trg_archive_produit();

-- Archivage utilisateur
CREATE OR REPLACE FUNCTION trg_archive_utilisateur()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
        INSERT INTO archive_xml(entite, id_entite, xml_data, action)
        VALUES ('utilisateur', NEW.id_utilisateur, row_to_json(NEW)::TEXT, 'suppression');
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_archive_user
AFTER UPDATE ON utilisateur
FOR EACH ROW EXECUTE FUNCTION trg_archive_utilisateur();

-- Archivage groupe utilisateur
CREATE OR REPLACE FUNCTION trg_archive_groupe()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
        INSERT INTO archive_xml(entite, id_entite, xml_data, action)
        VALUES ('groupe_utilisateur', NEW.id_groupe, row_to_json(NEW)::TEXT, 'suppression');
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_archive_grp
AFTER UPDATE ON groupe_utilisateur
FOR EACH ROW EXECUTE FUNCTION trg_archive_groupe();

-- ================================================================
-- SÉQUENCES POUR NUMÉROTATION AUTOMATIQUE
-- ================================================================

CREATE SEQUENCE seq_bc_fournisseur START 1;
CREATE SEQUENCE seq_bc_client      START 1;
CREATE SEQUENCE seq_br             START 1;
CREATE SEQUENCE seq_bl             START 1;
CREATE SEQUENCE seq_facture_f      START 1;
CREATE SEQUENCE seq_facture_c      START 1;
CREATE SEQUENCE seq_bon_sortie     START 1;
CREATE SEQUENCE seq_bon_don        START 1;

-- Numérotation auto bon de commande fournisseur
CREATE OR REPLACE FUNCTION trg_numero_cf()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.numero_bc := 'BCF-' || TO_CHAR(NOW(),'YYYY') || '-'
                   || LPAD(nextval('seq_bc_fournisseur')::TEXT, 5, '0');
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_num_cf
BEFORE INSERT ON commande_fournisseur
FOR EACH ROW WHEN (NEW.numero_bc IS NULL)
EXECUTE FUNCTION trg_numero_cf();

-- Numérotation auto bon de commande client
CREATE OR REPLACE FUNCTION trg_numero_cc()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.numero_bc := 'BCC-' || TO_CHAR(NOW(),'YYYY') || '-'
                   || LPAD(nextval('seq_bc_client')::TEXT, 5, '0');
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_num_cc
BEFORE INSERT ON commande_client
FOR EACH ROW WHEN (NEW.numero_bc IS NULL)
EXECUTE FUNCTION trg_numero_cc();

-- Numérotation auto bon de réception
CREATE OR REPLACE FUNCTION trg_numero_br()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.numero_br := 'BR-' || TO_CHAR(NOW(),'YYYY') || '-'
                   || LPAD(nextval('seq_br')::TEXT, 5, '0');
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_num_br
BEFORE INSERT ON bon_reception
FOR EACH ROW WHEN (NEW.numero_br IS NULL)
EXECUTE FUNCTION trg_numero_br();

-- Numérotation auto bon de livraison
CREATE OR REPLACE FUNCTION trg_numero_bl()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.numero_bl := 'BL-' || TO_CHAR(NOW(),'YYYY') || '-'
                   || LPAD(nextval('seq_bl')::TEXT, 5, '0');
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_num_bl
BEFORE INSERT ON bon_livraison
FOR EACH ROW WHEN (NEW.numero_bl IS NULL)
EXECUTE FUNCTION trg_numero_bl();

-- Numérotation auto facture fournisseur
CREATE OR REPLACE FUNCTION trg_numero_ff()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.numero_facture := 'FF-' || TO_CHAR(NOW(),'YYYY') || '-'
                        || LPAD(nextval('seq_facture_f')::TEXT, 5, '0');
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_num_ff
BEFORE INSERT ON facture_fournisseur
FOR EACH ROW WHEN (NEW.numero_facture IS NULL)
EXECUTE FUNCTION trg_numero_ff();

-- Numérotation auto facture client
CREATE OR REPLACE FUNCTION trg_numero_fc()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.numero_facture := 'FC-' || TO_CHAR(NOW(),'YYYY') || '-'
                        || LPAD(nextval('seq_facture_c')::TEXT, 5, '0');
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_num_fc
BEFORE INSERT ON facture_client
FOR EACH ROW WHEN (NEW.numero_facture IS NULL)
EXECUTE FUNCTION trg_numero_fc();

-- ================================================================
-- VUES — ÉTATS ET RAPPORTS (module Édition)
-- ================================================================

-- Stock actuel avec alerte
CREATE VIEW v_stock_produit AS
SELECT
    p.id_produit,
    p.code,
    p.designation,
    f.libelle          AS famille,
    p.unite,
    p.stock_actuel,
    p.stock_alerte,
    p.prix_achat,
    p.prix_vente,
    (p.stock_actuel * p.prix_achat) AS valeur_stock,
    (p.stock_actuel <= p.stock_alerte) AS en_alerte
FROM produit p
JOIN famille_produit f ON f.id_famille = p.id_famille
WHERE p.deleted_at IS NULL
ORDER BY f.libelle, p.designation;

-- Liste des produits par famille
CREATE VIEW v_produits_par_famille AS
SELECT
    f.libelle  AS famille,
    p.code,
    p.designation,
    p.unite,
    p.prix_achat,
    p.prix_vente,
    p.stock_actuel,
    CASE WHEN p.id_produit_pere IS NOT NULL THEN 'fils' ELSE 'père' END AS type_produit
FROM produit p
JOIN famille_produit f ON f.id_famille = p.id_famille
WHERE p.deleted_at IS NULL
ORDER BY f.libelle, p.id_produit_pere NULLS FIRST, p.designation;

-- État des achats par jour
CREATE VIEW v_achats_par_jour AS
SELECT
    cf.date_commande                      AS jour,
    COUNT(DISTINCT cf.id_commande_f)      AS nb_commandes,
    SUM(l.quantite)                       AS total_quantite,
    SUM(l.montant_ligne)                  AS total_montant_ht
FROM commande_fournisseur cf
JOIN ligne_commande_f l ON l.id_commande_f = cf.id_commande_f
WHERE cf.deleted_at IS NULL
  AND cf.statut != 'annulee'
GROUP BY cf.date_commande
ORDER BY cf.date_commande DESC;

-- État des achats annuels
CREATE VIEW v_achats_annuels AS
SELECT
    EXTRACT(YEAR FROM cf.date_commande)   AS annee,
    EXTRACT(MONTH FROM cf.date_commande)  AS mois,
    COUNT(DISTINCT cf.id_commande_f)      AS nb_commandes,
    SUM(l.quantite)                       AS total_quantite,
    SUM(l.montant_ligne)                  AS total_montant_ht
FROM commande_fournisseur cf
JOIN ligne_commande_f l ON l.id_commande_f = cf.id_commande_f
WHERE cf.deleted_at IS NULL
  AND cf.statut != 'annulee'
GROUP BY EXTRACT(YEAR FROM cf.date_commande),
         EXTRACT(MONTH FROM cf.date_commande)
ORDER BY annee DESC, mois;

-- État des ventes par jour
CREATE VIEW v_ventes_par_jour AS
SELECT
    cc.date_commande                      AS jour,
    COUNT(DISTINCT cc.id_commande_c)      AS nb_commandes,
    SUM(l.quantite)                       AS total_quantite,
    SUM(l.montant_ligne)                  AS total_montant_ht
FROM commande_client cc
JOIN ligne_commande_c l ON l.id_commande_c = cc.id_commande_c
WHERE cc.deleted_at IS NULL
  AND cc.statut != 'annulee'
GROUP BY cc.date_commande
ORDER BY cc.date_commande DESC;

-- État des ventes annuelles
CREATE VIEW v_ventes_annuelles AS
SELECT
    EXTRACT(YEAR FROM cc.date_commande)   AS annee,
    EXTRACT(MONTH FROM cc.date_commande)  AS mois,
    COUNT(DISTINCT cc.id_commande_c)      AS nb_commandes,
    SUM(l.quantite)                       AS total_quantite,
    SUM(l.montant_ligne)                  AS total_montant_ht
FROM commande_client cc
JOIN ligne_commande_c l ON l.id_commande_c = cc.id_commande_c
WHERE cc.deleted_at IS NULL
  AND cc.statut != 'annulee'
GROUP BY EXTRACT(YEAR FROM cc.date_commande),
         EXTRACT(MONTH FROM cc.date_commande)
ORDER BY annee DESC, mois;

-- État des versements en banque par période
CREATE VIEW v_versements_banque AS
SELECT
    b.nom                         AS banque,
    b.numero_compte,
    COUNT(*)                      AS nb_versements,
    SUM(v.montant)                AS total_verse,
    MIN(v.date_versement)         AS premier_versement,
    MAX(v.date_versement)         AS dernier_versement
FROM versement_banque v
JOIN banque b ON b.id_banque = v.id_banque
GROUP BY b.id_banque, b.nom, b.numero_compte
ORDER BY b.nom;

-- Factures impayées (fournisseurs)
CREATE VIEW v_factures_f_impayees AS
SELECT
    ff.numero_facture,
    f.nom          AS fournisseur,
    ff.date_facture,
    ff.montant_ttc,
    COALESCE(SUM(r.montant), 0)          AS montant_regle,
    ff.montant_ttc - COALESCE(SUM(r.montant), 0) AS reste_a_payer
FROM facture_fournisseur ff
JOIN commande_fournisseur cf ON cf.id_commande_f = ff.id_commande_f
JOIN fournisseur f ON f.id_fournisseur = cf.id_fournisseur
LEFT JOIN reglement_fournisseur r ON r.id_facture_f = ff.id_facture_f
WHERE ff.statut_paiement != 'soldee'
GROUP BY ff.id_facture_f, ff.numero_facture, f.nom,
         ff.date_facture, ff.montant_ttc
ORDER BY ff.date_facture;

-- Factures impayées (clients)
CREATE VIEW v_factures_c_impayees AS
SELECT
    fc.numero_facture,
    c.nom          AS client,
    fc.date_facture,
    fc.montant_ttc,
    COALESCE(SUM(r.montant), 0)          AS montant_regle,
    fc.montant_ttc - COALESCE(SUM(r.montant), 0) AS reste_a_payer
FROM facture_client fc
JOIN commande_client cc ON cc.id_commande_c = fc.id_commande_c
JOIN client c ON c.id_client = cc.id_client
LEFT JOIN reglement_client r ON r.id_facture_c = fc.id_facture_c
WHERE fc.statut_paiement != 'soldee'
GROUP BY fc.id_facture_c, fc.numero_facture, c.nom,
         fc.date_facture, fc.montant_ttc
ORDER BY fc.date_facture;

-- Corbeille (éléments supprimés restaurables)
CREATE VIEW v_corbeille AS
SELECT entite, id_entite, action, created_at
FROM archive_xml
WHERE action = 'suppression'
  AND (entite, id_entite, created_at) IN (
      SELECT entite, id_entite, MAX(created_at)
      FROM archive_xml
      WHERE action = 'suppression'
      GROUP BY entite, id_entite
  )
ORDER BY created_at DESC;

-- ================================================================
-- DONNÉES INITIALES
-- ================================================================

INSERT INTO categorie_client(libelle, remise_pct) VALUES
    ('Standard',   0.00),
    ('Grossiste',  5.00),
    ('Revendeur',  8.00),
    ('VIP',       10.00);

INSERT INTO groupe_utilisateur(libelle, description) VALUES
    ('Administrateur', 'Accès total à tous les modules'),
    ('Gestionnaire',   'Approvisionnements et ventes'),
    ('Caissier',       'Ventes au comptant uniquement'),
    ('Magasinier',     'Réceptions et bons de sortie'),
    ('Consultant',     'Lecture seule — aucune modification');

-- Droits complets pour Administrateur (id=1)
INSERT INTO droit(id_groupe, module, action, autorise)
SELECT 1, m.module, a.action, TRUE
FROM (VALUES
    ('approvisionnement'),('vente'),
    ('structure'),('securite')
) AS m(module)
CROSS JOIN (VALUES
    ('creer'),('modifier'),('supprimer'),
    ('imprimer'),('consulter'),('regler')
) AS a(action);

-- Droits Gestionnaire (id=2)
INSERT INTO droit(id_groupe, module, action, autorise)
SELECT 2, m.module, a.action, TRUE
FROM (VALUES
    ('approvisionnement'),('vente'),('structure')
) AS m(module)
CROSS JOIN (VALUES
    ('creer'),('modifier'),('imprimer'),('consulter'),('regler')
) AS a(action);

-- Droits Caissier (id=3) — ventes uniquement
INSERT INTO droit(id_groupe, module, action, autorise)
SELECT 3, 'vente', a.action, TRUE
FROM (VALUES
    ('creer'),('imprimer'),('consulter'),('regler')
) AS a(action);

-- Droits Magasinier (id=4) — appro consultation + réception
INSERT INTO droit(id_groupe, module, action, autorise)
VALUES
    (4, 'approvisionnement', 'creer',     TRUE),
    (4, 'approvisionnement', 'consulter', TRUE),
    (4, 'approvisionnement', 'imprimer',  TRUE),
    (4, 'structure',         'consulter', TRUE);

-- Droits Consultant (id=5) — lecture seule
INSERT INTO droit(id_groupe, module, action, autorise)
SELECT 5, m.module, 'consulter', TRUE
FROM (VALUES
    ('approvisionnement'),('vente'),
    ('structure'),('securite')
) AS m(module);

COMMIT;

-- ================================================================
-- FIN DU SCRIPT — Gestion de Stock (PostgreSQL)
-- Total : 27 tables, 6 vues, 15 triggers, 8 séquences
-- ================================================================