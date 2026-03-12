--
-- PostgreSQL database dump
--

\restrict TiMKx0Q7l5uGoimJhw5I9geyQ75fETgJ3HVASgkmC0cbhsC16U5z2JdukQMSVIz

-- Dumped from database version 18.3
-- Dumped by pg_dump version 18.3

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: api; Type: SCHEMA; Schema: -; Owner: mammopiga
--

CREATE SCHEMA api;


ALTER SCHEMA api OWNER TO mammopiga;

--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- Name: ruolo_utente; Type: TYPE; Schema: public; Owner: mammopiga
--

CREATE TYPE public.ruolo_utente AS ENUM (
    'utente',
    'negoziante',
    'admin'
);


ALTER TYPE public.ruolo_utente OWNER TO mammopiga;

--
-- Name: stato_evento; Type: TYPE; Schema: public; Owner: mammopiga
--

CREATE TYPE public.stato_evento AS ENUM (
    'in_attesa',
    'approvato',
    'rifiutato'
);


ALTER TYPE public.stato_evento OWNER TO mammopiga;

--
-- Name: stato_segnalazione; Type: TYPE; Schema: public; Owner: mammopiga
--

CREATE TYPE public.stato_segnalazione AS ENUM (
    'inviata',
    'in_verifica',
    'risolta'
);


ALTER TYPE public.stato_segnalazione OWNER TO mammopiga;

--
-- Name: eventi_vicini(double precision, double precision, integer); Type: FUNCTION; Schema: api; Owner: mammopiga
--

CREATE FUNCTION api.eventi_vicini(lat double precision, lon double precision, raggio integer) RETURNS TABLE(id integer, titolo text, descrizione text, indirizzo text, data_evento date, distanza_m integer)
    LANGUAGE sql STABLE
    AS $$
SELECT
e.id,
e.titolo,
e.descrizione,
e.indirizzo,
e.data_evento,
ST_Distance(
e.posizione,
ST_SetSRID(ST_MakePoint(lon,lat),4326)::geography
)::INTEGER AS distanza_m
FROM eventi e
WHERE e.stato = 'approvato'
AND ST_DWithin(
e.posizione,
ST_SetSRID(ST_MakePoint(lon,lat),4326)::geography,
raggio
)
ORDER BY distanza_m ASC;
$$;


ALTER FUNCTION api.eventi_vicini(lat double precision, lon double precision, raggio integer) OWNER TO mammopiga;

--
-- Name: home(); Type: FUNCTION; Schema: api; Owner: postgres
--

CREATE FUNCTION api.home() RETURNS json
    LANGUAGE sql STABLE
    AS $$

SELECT json_build_object(

'eventi',
(
    SELECT json_agg(e)
    FROM (
        SELECT
            id,
            titolo,
            descrizione,
            data_evento,
            indirizzo
        FROM eventi
        WHERE stato = 'approvato'
        AND data_evento >= CURRENT_DATE
        ORDER BY data_evento
        LIMIT 10
    ) e
),

'offerte',
(
    SELECT json_agg(o)
    FROM (
        SELECT
            o.id,
            o.titolo,
            o.descrizione,
            n.nome AS negozio
        FROM offerte o
        JOIN negozi n ON n.id = o.negozio_id
        ORDER BY o.id DESC
        LIMIT 10
    ) o
),

'comunicazioni',
(
    SELECT json_agg(c)
    FROM (
        SELECT
            id,
            titolo,
            contenuto,
            data_pubblicazione
        FROM comunicazioni_led
        ORDER BY data_pubblicazione DESC
        LIMIT 5
    ) c
)

);

$$;


ALTER FUNCTION api.home() OWNER TO postgres;

--
-- Name: mappa_citta(); Type: FUNCTION; Schema: api; Owner: mammopiga
--

CREATE FUNCTION api.mappa_citta() RETURNS TABLE(tipo text, id integer, nome text, lat double precision, lon double precision)
    LANGUAGE sql STABLE
    AS $$

-- EVENTI
SELECT
'evento',
e.id,
e.titolo,
ST_Y(e.posizione::geometry),
ST_X(e.posizione::geometry)
FROM public.eventi e
WHERE e.stato = 'approvato'

UNION ALL

-- NEGOZI
SELECT
'negozio',
n.id,
n.nome,
ST_Y(n.posizione::geometry),
ST_X(n.posizione::geometry)
FROM public.negozi n
WHERE n.approvato = true

UNION ALL

-- SEGNALAZIONI
SELECT
'segnalazione',
s.id,
s.titolo,
ST_Y(s.posizione::geometry),
ST_X(s.posizione::geometry)
FROM public.segnalazioni s;

$$;


ALTER FUNCTION api.mappa_citta() OWNER TO mammopiga;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: eventi; Type: TABLE; Schema: public; Owner: mammopiga
--

CREATE TABLE public.eventi (
    id integer NOT NULL,
    titolo character varying(200) NOT NULL,
    descrizione text,
    indirizzo text,
    posizione public.geography(Point,4326),
    data_evento date,
    ora_evento time without time zone,
    negozio_id integer,
    creato_da integer,
    stato public.stato_evento DEFAULT 'in_attesa'::public.stato_evento,
    approvato_da integer,
    data_creazione timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    data_approvazione timestamp without time zone,
    citta_id integer NOT NULL
);


ALTER TABLE public.eventi OWNER TO mammopiga;

--
-- Name: approva_evento(integer, integer); Type: FUNCTION; Schema: public; Owner: mammopiga
--

CREATE FUNCTION public.approva_evento(evento_id integer, admin_id integer) RETURNS public.eventi
    LANGUAGE sql
    AS $$
UPDATE eventi
SET
stato = 'approvato',
approvato_da = admin_id,
data_approvazione = CURRENT_TIMESTAMP
WHERE id = evento_id
RETURNING *;
$$;


ALTER FUNCTION public.approva_evento(evento_id integer, admin_id integer) OWNER TO mammopiga;

--
-- Name: crea_evento(text, text, date, time without time zone); Type: FUNCTION; Schema: public; Owner: mammopiga
--

CREATE FUNCTION public.crea_evento(titolo text, descrizione text, data_evento date, ora_evento time without time zone) RETURNS public.eventi
    LANGUAGE sql
    AS $$
INSERT INTO eventi (
titolo,
descrizione,
data_evento,
ora_evento,
stato
)
VALUES (
titolo,
descrizione,
data_evento,
ora_evento,
'in_attesa'
)
RETURNING *;
$$;


ALTER FUNCTION public.crea_evento(titolo text, descrizione text, data_evento date, ora_evento time without time zone) OWNER TO mammopiga;

--
-- Name: crea_notifica_evento(); Type: FUNCTION; Schema: public; Owner: mammopiga
--

CREATE FUNCTION public.crea_notifica_evento() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

IF NEW.stato = 'approvato' AND OLD.stato <> 'approvato' THEN

INSERT INTO notifiche (
titolo,
messaggio,
tipo,
evento_id
)
VALUES (
'Nuovo evento in città',
NEW.titolo,
'evento',
NEW.id
);

END IF;

RETURN NEW;

END;
$$;


ALTER FUNCTION public.crea_notifica_evento() OWNER TO mammopiga;

--
-- Name: notifica_evento_approvato(); Type: FUNCTION; Schema: public; Owner: mammopiga
--

CREATE FUNCTION public.notifica_evento_approvato() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

IF NEW.stato = 'approvato' AND OLD.stato <> 'approvato' THEN

INSERT INTO notifiche (titolo, messaggio)
VALUES (
'Nuovo evento approvato',
'È stato approvato un nuovo evento: ' || NEW.titolo
);

END IF;

RETURN NEW;

END;
$$;


ALTER FUNCTION public.notifica_evento_approvato() OWNER TO mammopiga;

--
-- Name: rifiuta_evento(integer); Type: FUNCTION; Schema: public; Owner: mammopiga
--

CREATE FUNCTION public.rifiuta_evento(evento_id integer) RETURNS public.eventi
    LANGUAGE sql
    AS $$
UPDATE eventi
SET stato = 'rifiutato'
WHERE id = evento_id
RETURNING *;
$$;


ALTER FUNCTION public.rifiuta_evento(evento_id integer) OWNER TO mammopiga;

--
-- Name: negozi; Type: TABLE; Schema: public; Owner: mammopiga
--

CREATE TABLE public.negozi (
    id integer NOT NULL,
    nome character varying(150) NOT NULL,
    descrizione text,
    indirizzo text,
    posizione public.geography(Point,4326),
    telefono character varying(50),
    email character varying(150),
    categoria_id integer,
    approvato boolean DEFAULT false,
    creato_da integer,
    data_creazione timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    proprietario_id integer,
    citta_id integer NOT NULL
);


ALTER TABLE public.negozi OWNER TO mammopiga;

--
-- Name: api_eventi_pubblici; Type: VIEW; Schema: api; Owner: mammopiga
--

CREATE VIEW api.api_eventi_pubblici AS
 SELECT e.id,
    e.titolo,
    e.descrizione,
    e.data_evento,
    e.ora_evento,
    n.nome AS negozio,
    public.st_x((e.posizione)::public.geometry) AS longitudine,
    public.st_y((e.posizione)::public.geometry) AS latitudine
   FROM (public.eventi e
     LEFT JOIN public.negozi n ON ((e.negozio_id = n.id)))
  WHERE ((e.stato = 'approvato'::public.stato_evento) AND (e.data_evento >= CURRENT_DATE));


ALTER VIEW api.api_eventi_pubblici OWNER TO mammopiga;

--
-- Name: citta; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.citta (
    id integer NOT NULL,
    nome character varying(150) NOT NULL,
    provincia character varying(50),
    regione character varying(100),
    slug character varying(150),
    lat double precision,
    lon double precision,
    attiva boolean DEFAULT true,
    data_creazione timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    cliente_id integer,
    logo_url text,
    colore_primario character varying(20),
    sito_web text
);


ALTER TABLE public.citta OWNER TO postgres;

--
-- Name: comunicazioni_led; Type: TABLE; Schema: public; Owner: mammopiga
--

CREATE TABLE public.comunicazioni_led (
    id integer NOT NULL,
    titolo character varying(200),
    contenuto text,
    pubblicato_da integer,
    data_pubblicazione timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    immagine_url text,
    citta_id integer NOT NULL
);


ALTER TABLE public.comunicazioni_led OWNER TO mammopiga;

--
-- Name: offerte; Type: TABLE; Schema: public; Owner: mammopiga
--

CREATE TABLE public.offerte (
    id integer NOT NULL,
    negozio_id integer NOT NULL,
    titolo character varying(200),
    descrizione text,
    sconto_percentuale integer,
    data_inizio date,
    data_fine date,
    attiva boolean DEFAULT true,
    citta_id integer NOT NULL
);


ALTER TABLE public.offerte OWNER TO mammopiga;

--
-- Name: api_home; Type: VIEW; Schema: api; Owner: mammopiga
--

CREATE VIEW api.api_home AS
 SELECT 'e'::text AS tipo,
    e.id,
    e.titolo,
    e.descrizione,
    e.data_evento AS data,
    e.indirizzo,
    c.nome AS citta,
    c.slug AS citta_slug,
    public.st_y((e.posizione)::public.geometry) AS lat,
    public.st_x((e.posizione)::public.geometry) AS lng
   FROM (public.eventi e
     JOIN public.citta c ON ((e.citta_id = c.id)))
  WHERE (e.stato = 'approvato'::public.stato_evento)
UNION ALL
 SELECT 'c'::text AS tipo,
    cl.id,
    cl.titolo,
    cl.contenuto AS descrizione,
    cl.data_pubblicazione AS data,
    NULL::text AS indirizzo,
    c.nome AS citta,
    c.slug AS citta_slug,
    NULL::double precision AS lat,
    NULL::double precision AS lng
   FROM (public.comunicazioni_led cl
     JOIN public.citta c ON ((cl.citta_id = c.id)))
UNION ALL
 SELECT 'o'::text AS tipo,
    o.id,
    o.titolo,
    o.descrizione,
    o.data_fine AS data,
    n.indirizzo,
    c.nome AS citta,
    c.slug AS citta_slug,
    public.st_y((n.posizione)::public.geometry) AS lat,
    public.st_x((n.posizione)::public.geometry) AS lng
   FROM ((public.offerte o
     JOIN public.negozi n ON ((o.negozio_id = n.id)))
     JOIN public.citta c ON ((n.citta_id = c.id)))
  WHERE (o.attiva = true);


ALTER VIEW api.api_home OWNER TO mammopiga;

--
-- Name: segnalazioni; Type: TABLE; Schema: public; Owner: mammopiga
--

CREATE TABLE public.segnalazioni (
    id integer NOT NULL,
    utente_id integer,
    titolo character varying(200) NOT NULL,
    descrizione text,
    stato public.stato_segnalazione DEFAULT 'inviata'::public.stato_segnalazione,
    posizione public.geography(Point,4326),
    data_creazione timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    citta_id integer NOT NULL
);


ALTER TABLE public.segnalazioni OWNER TO mammopiga;

--
-- Name: api_mappa; Type: VIEW; Schema: api; Owner: mammopiga
--

CREATE VIEW api.api_mappa AS
 SELECT 'evento'::text AS tipo,
    e.id,
    e.titolo,
    e.descrizione,
    c.nome AS citta,
    c.slug AS citta_slug,
    public.st_y((e.posizione)::public.geometry) AS lat,
    public.st_x((e.posizione)::public.geometry) AS lng
   FROM (public.eventi e
     JOIN public.citta c ON ((e.citta_id = c.id)))
  WHERE (e.stato = 'approvato'::public.stato_evento)
UNION ALL
 SELECT 'negozio'::text AS tipo,
    n.id,
    n.nome AS titolo,
    n.descrizione,
    c.nome AS citta,
    c.slug AS citta_slug,
    public.st_y((n.posizione)::public.geometry) AS lat,
    public.st_x((n.posizione)::public.geometry) AS lng
   FROM (public.negozi n
     JOIN public.citta c ON ((n.citta_id = c.id)))
  WHERE (n.approvato = true)
UNION ALL
 SELECT 'segnalazione'::text AS tipo,
    s.id,
    s.titolo,
    s.descrizione,
    c.nome AS citta,
    c.slug AS citta_slug,
    public.st_y((s.posizione)::public.geometry) AS lat,
    public.st_x((s.posizione)::public.geometry) AS lng
   FROM (public.segnalazioni s
     JOIN public.citta c ON ((s.citta_id = c.id)));


ALTER VIEW api.api_mappa OWNER TO mammopiga;

--
-- Name: eventi_home; Type: VIEW; Schema: api; Owner: mammopiga
--

CREATE VIEW api.eventi_home AS
 SELECT id,
    titolo,
    descrizione,
    data_evento,
    ora_evento
   FROM public.eventi
  WHERE (stato = 'approvato'::public.stato_evento)
  ORDER BY data_evento;


ALTER VIEW api.eventi_home OWNER TO mammopiga;

--
-- Name: eventi_pubblici; Type: VIEW; Schema: api; Owner: mammopiga
--

CREATE VIEW api.eventi_pubblici AS
 SELECT e.id,
    e.titolo,
    e.descrizione,
    e.data_evento,
    e.ora_evento,
    e.indirizzo,
    c.nome AS citta,
    c.slug AS citta_slug,
    n.nome AS negozio,
    public.st_x((e.posizione)::public.geometry) AS longitudine,
    public.st_y((e.posizione)::public.geometry) AS latitudine
   FROM ((public.eventi e
     JOIN public.citta c ON ((e.citta_id = c.id)))
     LEFT JOIN public.negozi n ON ((e.negozio_id = n.id)))
  WHERE (e.stato = 'approvato'::public.stato_evento);


ALTER VIEW api.eventi_pubblici OWNER TO mammopiga;

--
-- Name: negozi; Type: VIEW; Schema: api; Owner: mammopiga
--

CREATE VIEW api.negozi AS
 SELECT id,
    nome,
    descrizione
   FROM public.negozi;


ALTER VIEW api.negozi OWNER TO mammopiga;

--
-- Name: notifiche; Type: TABLE; Schema: public; Owner: mammopiga
--

CREATE TABLE public.notifiche (
    id integer NOT NULL,
    utente_id integer,
    titolo character varying(200) NOT NULL,
    messaggio text NOT NULL,
    letto boolean DEFAULT false,
    data_invio timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.notifiche OWNER TO mammopiga;

--
-- Name: notifiche; Type: VIEW; Schema: api; Owner: mammopiga
--

CREATE VIEW api.notifiche AS
 SELECT id,
    utente_id,
    titolo,
    messaggio,
    letto,
    data_invio
   FROM public.notifiche
  ORDER BY data_invio DESC;


ALTER VIEW api.notifiche OWNER TO mammopiga;

--
-- Name: offerte_attive; Type: VIEW; Schema: api; Owner: mammopiga
--

CREATE VIEW api.offerte_attive AS
 SELECT o.id,
    o.titolo,
    o.descrizione,
    n.nome AS negozio
   FROM (public.offerte o
     JOIN public.negozi n ON ((o.negozio_id = n.id)))
  WHERE (o.attiva = true);


ALTER VIEW api.offerte_attive OWNER TO mammopiga;

--
-- Name: view_comunicazioni_led; Type: VIEW; Schema: api; Owner: mammopiga
--

CREATE VIEW api.view_comunicazioni_led AS
 SELECT id,
    titolo,
    contenuto,
    immagine_url,
    data_pubblicazione
   FROM public.comunicazioni_led
  ORDER BY data_pubblicazione DESC;


ALTER VIEW api.view_comunicazioni_led OWNER TO mammopiga;

--
-- Name: eventi_immagini; Type: TABLE; Schema: public; Owner: mammopiga
--

CREATE TABLE public.eventi_immagini (
    id integer NOT NULL,
    evento_id integer NOT NULL,
    url text NOT NULL,
    descrizione text,
    caricata_il timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.eventi_immagini OWNER TO mammopiga;

--
-- Name: view_eventi_dettaglio; Type: VIEW; Schema: api; Owner: mammopiga
--

CREATE VIEW api.view_eventi_dettaglio AS
 SELECT e.id,
    e.titolo,
    e.descrizione,
    e.data_evento,
    e.ora_evento,
    i.url AS immagine
   FROM (public.eventi e
     LEFT JOIN public.eventi_immagini i ON ((e.id = i.evento_id)))
  WHERE (e.stato = 'approvato'::public.stato_evento);


ALTER VIEW api.view_eventi_dettaglio OWNER TO mammopiga;

--
-- Name: view_eventi_home; Type: VIEW; Schema: api; Owner: mammopiga
--

CREATE VIEW api.view_eventi_home AS
 SELECT e.id,
    e.titolo,
    e.descrizione,
    e.data_evento,
    e.ora_evento,
    n.nome AS negozio,
    public.st_x((e.posizione)::public.geometry) AS longitudine,
    public.st_y((e.posizione)::public.geometry) AS latitudine
   FROM (public.eventi e
     LEFT JOIN public.negozi n ON ((e.negozio_id = n.id)))
  WHERE ((e.stato = 'approvato'::public.stato_evento) AND (e.data_evento >= CURRENT_DATE))
  ORDER BY e.data_evento;


ALTER VIEW api.view_eventi_home OWNER TO mammopiga;

--
-- Name: categorie; Type: TABLE; Schema: public; Owner: mammopiga
--

CREATE TABLE public.categorie (
    id integer NOT NULL,
    nome character varying(100) NOT NULL
);


ALTER TABLE public.categorie OWNER TO mammopiga;

--
-- Name: view_negozi; Type: VIEW; Schema: api; Owner: mammopiga
--

CREATE VIEW api.view_negozi AS
 SELECT n.id,
    n.nome,
    n.descrizione,
    c.nome AS categoria,
    public.st_x((n.posizione)::public.geometry) AS longitudine,
    public.st_y((n.posizione)::public.geometry) AS latitudine
   FROM (public.negozi n
     LEFT JOIN public.categorie c ON ((n.categoria_id = c.id)));


ALTER VIEW api.view_negozi OWNER TO mammopiga;

--
-- Name: view_notifiche; Type: VIEW; Schema: api; Owner: mammopiga
--

CREATE VIEW api.view_notifiche AS
 SELECT id,
    utente_id,
    titolo,
    messaggio,
    letto,
    data_invio
   FROM public.notifiche
  ORDER BY data_invio DESC;


ALTER VIEW api.view_notifiche OWNER TO mammopiga;

--
-- Name: view_offerte_attive; Type: VIEW; Schema: api; Owner: mammopiga
--

CREATE VIEW api.view_offerte_attive AS
 SELECT o.id,
    o.titolo,
    o.descrizione,
    o.sconto_percentuale,
    n.nome AS negozio,
    o.data_fine
   FROM (public.offerte o
     JOIN public.negozi n ON ((o.negozio_id = n.id)))
  WHERE (((CURRENT_DATE >= o.data_inizio) AND (CURRENT_DATE <= o.data_fine)) AND (o.attiva = true));


ALTER VIEW api.view_offerte_attive OWNER TO mammopiga;

--
-- Name: view_segnalazioni_mappa; Type: VIEW; Schema: api; Owner: mammopiga
--

CREATE VIEW api.view_segnalazioni_mappa AS
 SELECT id,
    titolo,
    descrizione,
    stato,
    public.st_x((posizione)::public.geometry) AS longitudine,
    public.st_y((posizione)::public.geometry) AS latitudine,
    data_creazione
   FROM public.segnalazioni;


ALTER VIEW api.view_segnalazioni_mappa OWNER TO mammopiga;

--
-- Name: api_eventi_da_approvare; Type: VIEW; Schema: public; Owner: mammopiga
--

CREATE VIEW public.api_eventi_da_approvare AS
 SELECT id,
    titolo,
    descrizione,
    indirizzo,
    posizione,
    data_evento,
    ora_evento,
    negozio_id,
    creato_da,
    stato,
    approvato_da,
    data_creazione,
    data_approvazione
   FROM public.eventi
  WHERE (stato = 'in_attesa'::public.stato_evento);


ALTER VIEW public.api_eventi_da_approvare OWNER TO mammopiga;

--
-- Name: api_eventi_pubblici; Type: VIEW; Schema: public; Owner: mammopiga
--

CREATE VIEW public.api_eventi_pubblici AS
 SELECT e.id,
    e.titolo,
    e.descrizione,
    e.data_evento,
    e.ora_evento,
    e.indirizzo,
    c.nome AS citta,
    c.slug AS citta_slug,
    n.nome AS negozio,
    public.st_x((e.posizione)::public.geometry) AS longitudine,
    public.st_y((e.posizione)::public.geometry) AS latitudine
   FROM ((public.eventi e
     JOIN public.citta c ON ((e.citta_id = c.id)))
     LEFT JOIN public.negozi n ON ((e.negozio_id = n.id)))
  WHERE (e.stato = 'approvato'::public.stato_evento);


ALTER VIEW public.api_eventi_pubblici OWNER TO mammopiga;

--
-- Name: categorie_id_seq; Type: SEQUENCE; Schema: public; Owner: mammopiga
--

CREATE SEQUENCE public.categorie_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.categorie_id_seq OWNER TO mammopiga;

--
-- Name: categorie_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mammopiga
--

ALTER SEQUENCE public.categorie_id_seq OWNED BY public.categorie.id;


--
-- Name: citta_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.citta_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.citta_id_seq OWNER TO postgres;

--
-- Name: citta_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.citta_id_seq OWNED BY public.citta.id;


--
-- Name: clienti; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.clienti (
    id integer NOT NULL,
    nome character varying(200) NOT NULL,
    tipo character varying(50),
    email_contatto character varying(200),
    telefono character varying(50),
    data_attivazione timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    attivo boolean DEFAULT true
);


ALTER TABLE public.clienti OWNER TO postgres;

--
-- Name: clienti_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.clienti_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.clienti_id_seq OWNER TO postgres;

--
-- Name: clienti_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.clienti_id_seq OWNED BY public.clienti.id;


--
-- Name: comunicazioni_led_id_seq; Type: SEQUENCE; Schema: public; Owner: mammopiga
--

CREATE SEQUENCE public.comunicazioni_led_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.comunicazioni_led_id_seq OWNER TO mammopiga;

--
-- Name: comunicazioni_led_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mammopiga
--

ALTER SEQUENCE public.comunicazioni_led_id_seq OWNED BY public.comunicazioni_led.id;


--
-- Name: eventi_id_seq; Type: SEQUENCE; Schema: public; Owner: mammopiga
--

CREATE SEQUENCE public.eventi_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.eventi_id_seq OWNER TO mammopiga;

--
-- Name: eventi_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mammopiga
--

ALTER SEQUENCE public.eventi_id_seq OWNED BY public.eventi.id;


--
-- Name: eventi_immagini_id_seq; Type: SEQUENCE; Schema: public; Owner: mammopiga
--

CREATE SEQUENCE public.eventi_immagini_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.eventi_immagini_id_seq OWNER TO mammopiga;

--
-- Name: eventi_immagini_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mammopiga
--

ALTER SEQUENCE public.eventi_immagini_id_seq OWNED BY public.eventi_immagini.id;


--
-- Name: eventi_preferiti; Type: TABLE; Schema: public; Owner: mammopiga
--

CREATE TABLE public.eventi_preferiti (
    utente_id integer NOT NULL,
    evento_id integer NOT NULL,
    salvato_il timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.eventi_preferiti OWNER TO mammopiga;

--
-- Name: eventi_tag; Type: TABLE; Schema: public; Owner: mammopiga
--

CREATE TABLE public.eventi_tag (
    evento_id integer NOT NULL,
    tag_id integer NOT NULL
);


ALTER TABLE public.eventi_tag OWNER TO mammopiga;

--
-- Name: media; Type: TABLE; Schema: public; Owner: mammopiga
--

CREATE TABLE public.media (
    id integer NOT NULL,
    tipo_entita character varying(50) NOT NULL,
    entita_id integer NOT NULL,
    url text NOT NULL,
    tipo_media character varying(20) DEFAULT 'immagine'::character varying,
    descrizione text,
    ordine integer DEFAULT 0,
    caricata_il timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.media OWNER TO mammopiga;

--
-- Name: media_id_seq; Type: SEQUENCE; Schema: public; Owner: mammopiga
--

CREATE SEQUENCE public.media_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.media_id_seq OWNER TO mammopiga;

--
-- Name: media_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mammopiga
--

ALTER SEQUENCE public.media_id_seq OWNED BY public.media.id;


--
-- Name: negozi_id_seq; Type: SEQUENCE; Schema: public; Owner: mammopiga
--

CREATE SEQUENCE public.negozi_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.negozi_id_seq OWNER TO mammopiga;

--
-- Name: negozi_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mammopiga
--

ALTER SEQUENCE public.negozi_id_seq OWNED BY public.negozi.id;


--
-- Name: negozi_immagini; Type: TABLE; Schema: public; Owner: mammopiga
--

CREATE TABLE public.negozi_immagini (
    id integer NOT NULL,
    negozio_id integer NOT NULL,
    url text NOT NULL,
    descrizione text,
    caricata_il timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.negozi_immagini OWNER TO mammopiga;

--
-- Name: negozi_immagini_id_seq; Type: SEQUENCE; Schema: public; Owner: mammopiga
--

CREATE SEQUENCE public.negozi_immagini_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.negozi_immagini_id_seq OWNER TO mammopiga;

--
-- Name: negozi_immagini_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mammopiga
--

ALTER SEQUENCE public.negozi_immagini_id_seq OWNED BY public.negozi_immagini.id;


--
-- Name: notifiche_id_seq; Type: SEQUENCE; Schema: public; Owner: mammopiga
--

CREATE SEQUENCE public.notifiche_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.notifiche_id_seq OWNER TO mammopiga;

--
-- Name: notifiche_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mammopiga
--

ALTER SEQUENCE public.notifiche_id_seq OWNED BY public.notifiche.id;


--
-- Name: offerte_id_seq; Type: SEQUENCE; Schema: public; Owner: mammopiga
--

CREATE SEQUENCE public.offerte_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.offerte_id_seq OWNER TO mammopiga;

--
-- Name: offerte_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mammopiga
--

ALTER SEQUENCE public.offerte_id_seq OWNED BY public.offerte.id;


--
-- Name: preferiti; Type: TABLE; Schema: public; Owner: mammopiga
--

CREATE TABLE public.preferiti (
    id integer NOT NULL,
    utente_id integer,
    negozio_id integer
);


ALTER TABLE public.preferiti OWNER TO mammopiga;

--
-- Name: preferiti_id_seq; Type: SEQUENCE; Schema: public; Owner: mammopiga
--

CREATE SEQUENCE public.preferiti_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.preferiti_id_seq OWNER TO mammopiga;

--
-- Name: preferiti_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mammopiga
--

ALTER SEQUENCE public.preferiti_id_seq OWNED BY public.preferiti.id;


--
-- Name: segnalazioni_id_seq; Type: SEQUENCE; Schema: public; Owner: mammopiga
--

CREATE SEQUENCE public.segnalazioni_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.segnalazioni_id_seq OWNER TO mammopiga;

--
-- Name: segnalazioni_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mammopiga
--

ALTER SEQUENCE public.segnalazioni_id_seq OWNED BY public.segnalazioni.id;


--
-- Name: tag_eventi; Type: TABLE; Schema: public; Owner: mammopiga
--

CREATE TABLE public.tag_eventi (
    id integer NOT NULL,
    nome character varying(100) NOT NULL
);


ALTER TABLE public.tag_eventi OWNER TO mammopiga;

--
-- Name: tag_eventi_id_seq; Type: SEQUENCE; Schema: public; Owner: mammopiga
--

CREATE SEQUENCE public.tag_eventi_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.tag_eventi_id_seq OWNER TO mammopiga;

--
-- Name: tag_eventi_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mammopiga
--

ALTER SEQUENCE public.tag_eventi_id_seq OWNED BY public.tag_eventi.id;


--
-- Name: utenti; Type: TABLE; Schema: public; Owner: mammopiga
--

CREATE TABLE public.utenti (
    id integer NOT NULL,
    nome character varying(100),
    email character varying(150) NOT NULL,
    password text NOT NULL,
    ruolo public.ruolo_utente DEFAULT 'utente'::public.ruolo_utente,
    data_registrazione timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.utenti OWNER TO mammopiga;

--
-- Name: utenti_id_seq; Type: SEQUENCE; Schema: public; Owner: mammopiga
--

CREATE SEQUENCE public.utenti_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.utenti_id_seq OWNER TO mammopiga;

--
-- Name: utenti_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mammopiga
--

ALTER SEQUENCE public.utenti_id_seq OWNED BY public.utenti.id;


--
-- Name: utenti_profili; Type: TABLE; Schema: public; Owner: mammopiga
--

CREATE TABLE public.utenti_profili (
    id integer NOT NULL,
    utente_id integer,
    immagine_url text,
    bio text
);


ALTER TABLE public.utenti_profili OWNER TO mammopiga;

--
-- Name: utenti_profili_id_seq; Type: SEQUENCE; Schema: public; Owner: mammopiga
--

CREATE SEQUENCE public.utenti_profili_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.utenti_profili_id_seq OWNER TO mammopiga;

--
-- Name: utenti_profili_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: mammopiga
--

ALTER SEQUENCE public.utenti_profili_id_seq OWNED BY public.utenti_profili.id;


--
-- Name: categorie id; Type: DEFAULT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.categorie ALTER COLUMN id SET DEFAULT nextval('public.categorie_id_seq'::regclass);


--
-- Name: citta id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.citta ALTER COLUMN id SET DEFAULT nextval('public.citta_id_seq'::regclass);


--
-- Name: clienti id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clienti ALTER COLUMN id SET DEFAULT nextval('public.clienti_id_seq'::regclass);


--
-- Name: comunicazioni_led id; Type: DEFAULT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.comunicazioni_led ALTER COLUMN id SET DEFAULT nextval('public.comunicazioni_led_id_seq'::regclass);


--
-- Name: eventi id; Type: DEFAULT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.eventi ALTER COLUMN id SET DEFAULT nextval('public.eventi_id_seq'::regclass);


--
-- Name: eventi_immagini id; Type: DEFAULT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.eventi_immagini ALTER COLUMN id SET DEFAULT nextval('public.eventi_immagini_id_seq'::regclass);


--
-- Name: media id; Type: DEFAULT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.media ALTER COLUMN id SET DEFAULT nextval('public.media_id_seq'::regclass);


--
-- Name: negozi id; Type: DEFAULT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.negozi ALTER COLUMN id SET DEFAULT nextval('public.negozi_id_seq'::regclass);


--
-- Name: negozi_immagini id; Type: DEFAULT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.negozi_immagini ALTER COLUMN id SET DEFAULT nextval('public.negozi_immagini_id_seq'::regclass);


--
-- Name: notifiche id; Type: DEFAULT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.notifiche ALTER COLUMN id SET DEFAULT nextval('public.notifiche_id_seq'::regclass);


--
-- Name: offerte id; Type: DEFAULT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.offerte ALTER COLUMN id SET DEFAULT nextval('public.offerte_id_seq'::regclass);


--
-- Name: preferiti id; Type: DEFAULT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.preferiti ALTER COLUMN id SET DEFAULT nextval('public.preferiti_id_seq'::regclass);


--
-- Name: segnalazioni id; Type: DEFAULT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.segnalazioni ALTER COLUMN id SET DEFAULT nextval('public.segnalazioni_id_seq'::regclass);


--
-- Name: tag_eventi id; Type: DEFAULT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.tag_eventi ALTER COLUMN id SET DEFAULT nextval('public.tag_eventi_id_seq'::regclass);


--
-- Name: utenti id; Type: DEFAULT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.utenti ALTER COLUMN id SET DEFAULT nextval('public.utenti_id_seq'::regclass);


--
-- Name: utenti_profili id; Type: DEFAULT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.utenti_profili ALTER COLUMN id SET DEFAULT nextval('public.utenti_profili_id_seq'::regclass);


--
-- Data for Name: categorie; Type: TABLE DATA; Schema: public; Owner: mammopiga
--

COPY public.categorie (id, nome) FROM stdin;
1	Ristorante
2	Bar
3	Abbigliamento
4	Servizi
5	Artigianato
6	Benessere
7	Ristorante
8	Bar
9	Abbigliamento
10	Servizi
11	Artigianato
12	Benessere
13	Alimentari
14	Tecnologia
\.


--
-- Data for Name: citta; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.citta (id, nome, provincia, regione, slug, lat, lon, attiva, data_creazione, cliente_id, logo_url, colore_primario, sito_web) FROM stdin;
1	Fidenza	PR	Emilia-Romagna	fidenza	44.866	10.064	t	2026-03-12 00:04:26.194158	1	https://cityflow.it/loghi/fidenza.png	#2E86C1	\N
\.


--
-- Data for Name: clienti; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.clienti (id, nome, tipo, email_contatto, telefono, data_attivazione, attivo) FROM stdin;
1	Comune di Fidenza	comune	info@comune.fidenza.pr.it	\N	2026-03-12 00:08:40.581773	t
\.


--
-- Data for Name: comunicazioni_led; Type: TABLE DATA; Schema: public; Owner: mammopiga
--

COPY public.comunicazioni_led (id, titolo, contenuto, pubblicato_da, data_pubblicazione, immagine_url, citta_id) FROM stdin;
\.


--
-- Data for Name: eventi; Type: TABLE DATA; Schema: public; Owner: mammopiga
--

COPY public.eventi (id, titolo, descrizione, indirizzo, posizione, data_evento, ora_evento, negozio_id, creato_da, stato, approvato_da, data_creazione, data_approvazione, citta_id) FROM stdin;
1	Evento di prova	Evento di test per il database	\N	0101000020E6100000F6285C8FC215244066666666666E4640	2026-06-01	18:00:00	\N	\N	approvato	\N	2026-03-11 00:53:49.534502	\N	1
2	Evento di prova	Evento test per CityFlow	Piazza Garibaldi	0101000020E6100000F6285C8FC215244066666666666E4640	2026-06-01	\N	\N	\N	approvato	\N	2026-03-12 00:55:42.478469	\N	1
3	Evento di prova	Evento test per CityFlow	Piazza Garibaldi	0101000020E61000004BC8073D9B1524406688635DDC6E4640	2026-06-01	\N	\N	\N	approvato	\N	2026-03-12 00:55:49.19015	\N	1
\.


--
-- Data for Name: eventi_immagini; Type: TABLE DATA; Schema: public; Owner: mammopiga
--

COPY public.eventi_immagini (id, evento_id, url, descrizione, caricata_il) FROM stdin;
\.


--
-- Data for Name: eventi_preferiti; Type: TABLE DATA; Schema: public; Owner: mammopiga
--

COPY public.eventi_preferiti (utente_id, evento_id, salvato_il) FROM stdin;
\.


--
-- Data for Name: eventi_tag; Type: TABLE DATA; Schema: public; Owner: mammopiga
--

COPY public.eventi_tag (evento_id, tag_id) FROM stdin;
1	2
\.


--
-- Data for Name: media; Type: TABLE DATA; Schema: public; Owner: mammopiga
--

COPY public.media (id, tipo_entita, entita_id, url, tipo_media, descrizione, ordine, caricata_il) FROM stdin;
1	eventi	1	https://miosito.it/img/evento1.jpg	immagine	\N	0	2026-03-11 01:40:56.529878
2	negozi	3	https://miosito.it/img/negozio.jpg	immagine	\N	0	2026-03-11 01:41:03.554029
\.


--
-- Data for Name: negozi; Type: TABLE DATA; Schema: public; Owner: mammopiga
--

COPY public.negozi (id, nome, descrizione, indirizzo, posizione, telefono, email, categoria_id, approvato, creato_da, data_creazione, proprietario_id, citta_id) FROM stdin;
1	Bar Centrale	\N	Via Cavour 10	\N	\N	\N	\N	f	\N	2026-03-12 00:55:55.126524	\N	1
2	Bar Centrale	\N	Via Cavour 10	\N	\N	\N	\N	f	\N	2026-03-12 00:56:01.054151	\N	1
\.


--
-- Data for Name: negozi_immagini; Type: TABLE DATA; Schema: public; Owner: mammopiga
--

COPY public.negozi_immagini (id, negozio_id, url, descrizione, caricata_il) FROM stdin;
\.


--
-- Data for Name: notifiche; Type: TABLE DATA; Schema: public; Owner: mammopiga
--

COPY public.notifiche (id, utente_id, titolo, messaggio, letto, data_invio) FROM stdin;
\.


--
-- Data for Name: offerte; Type: TABLE DATA; Schema: public; Owner: mammopiga
--

COPY public.offerte (id, negozio_id, titolo, descrizione, sconto_percentuale, data_inizio, data_fine, attiva, citta_id) FROM stdin;
\.


--
-- Data for Name: preferiti; Type: TABLE DATA; Schema: public; Owner: mammopiga
--

COPY public.preferiti (id, utente_id, negozio_id) FROM stdin;
\.


--
-- Data for Name: segnalazioni; Type: TABLE DATA; Schema: public; Owner: mammopiga
--

COPY public.segnalazioni (id, utente_id, titolo, descrizione, stato, posizione, data_creazione, citta_id) FROM stdin;
\.


--
-- Data for Name: spatial_ref_sys; Type: TABLE DATA; Schema: public; Owner: mammopiga
--

COPY public.spatial_ref_sys (srid, auth_name, auth_srid, srtext, proj4text) FROM stdin;
\.


--
-- Data for Name: tag_eventi; Type: TABLE DATA; Schema: public; Owner: mammopiga
--

COPY public.tag_eventi (id, nome) FROM stdin;
1	musica
2	mercatino
3	famiglia
4	cultura
5	sport
\.


--
-- Data for Name: utenti; Type: TABLE DATA; Schema: public; Owner: mammopiga
--

COPY public.utenti (id, nome, email, password, ruolo, data_registrazione) FROM stdin;
1	Admin LeD	admin@ledfidenza.it	password_hash	admin	2026-03-11 00:44:16.758747
\.


--
-- Data for Name: utenti_profili; Type: TABLE DATA; Schema: public; Owner: mammopiga
--

COPY public.utenti_profili (id, utente_id, immagine_url, bio) FROM stdin;
\.


--
-- Name: categorie_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mammopiga
--

SELECT pg_catalog.setval('public.categorie_id_seq', 14, true);


--
-- Name: citta_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.citta_id_seq', 1, true);


--
-- Name: clienti_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.clienti_id_seq', 1, true);


--
-- Name: comunicazioni_led_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mammopiga
--

SELECT pg_catalog.setval('public.comunicazioni_led_id_seq', 1, false);


--
-- Name: eventi_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mammopiga
--

SELECT pg_catalog.setval('public.eventi_id_seq', 3, true);


--
-- Name: eventi_immagini_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mammopiga
--

SELECT pg_catalog.setval('public.eventi_immagini_id_seq', 1, false);


--
-- Name: media_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mammopiga
--

SELECT pg_catalog.setval('public.media_id_seq', 2, true);


--
-- Name: negozi_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mammopiga
--

SELECT pg_catalog.setval('public.negozi_id_seq', 2, true);


--
-- Name: negozi_immagini_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mammopiga
--

SELECT pg_catalog.setval('public.negozi_immagini_id_seq', 1, false);


--
-- Name: notifiche_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mammopiga
--

SELECT pg_catalog.setval('public.notifiche_id_seq', 1, false);


--
-- Name: offerte_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mammopiga
--

SELECT pg_catalog.setval('public.offerte_id_seq', 1, false);


--
-- Name: preferiti_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mammopiga
--

SELECT pg_catalog.setval('public.preferiti_id_seq', 1, false);


--
-- Name: segnalazioni_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mammopiga
--

SELECT pg_catalog.setval('public.segnalazioni_id_seq', 1, false);


--
-- Name: tag_eventi_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mammopiga
--

SELECT pg_catalog.setval('public.tag_eventi_id_seq', 5, true);


--
-- Name: utenti_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mammopiga
--

SELECT pg_catalog.setval('public.utenti_id_seq', 2, true);


--
-- Name: utenti_profili_id_seq; Type: SEQUENCE SET; Schema: public; Owner: mammopiga
--

SELECT pg_catalog.setval('public.utenti_profili_id_seq', 1, false);


--
-- Name: categorie categorie_pkey; Type: CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.categorie
    ADD CONSTRAINT categorie_pkey PRIMARY KEY (id);


--
-- Name: citta citta_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.citta
    ADD CONSTRAINT citta_pkey PRIMARY KEY (id);


--
-- Name: citta citta_slug_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.citta
    ADD CONSTRAINT citta_slug_key UNIQUE (slug);


--
-- Name: clienti clienti_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clienti
    ADD CONSTRAINT clienti_pkey PRIMARY KEY (id);


--
-- Name: comunicazioni_led comunicazioni_led_pkey; Type: CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.comunicazioni_led
    ADD CONSTRAINT comunicazioni_led_pkey PRIMARY KEY (id);


--
-- Name: eventi_immagini eventi_immagini_pkey; Type: CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.eventi_immagini
    ADD CONSTRAINT eventi_immagini_pkey PRIMARY KEY (id);


--
-- Name: eventi eventi_pkey; Type: CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.eventi
    ADD CONSTRAINT eventi_pkey PRIMARY KEY (id);


--
-- Name: eventi_preferiti eventi_preferiti_pkey; Type: CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.eventi_preferiti
    ADD CONSTRAINT eventi_preferiti_pkey PRIMARY KEY (utente_id, evento_id);


--
-- Name: eventi_tag eventi_tag_pkey; Type: CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.eventi_tag
    ADD CONSTRAINT eventi_tag_pkey PRIMARY KEY (evento_id, tag_id);


--
-- Name: media media_pkey; Type: CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.media
    ADD CONSTRAINT media_pkey PRIMARY KEY (id);


--
-- Name: negozi_immagini negozi_immagini_pkey; Type: CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.negozi_immagini
    ADD CONSTRAINT negozi_immagini_pkey PRIMARY KEY (id);


--
-- Name: negozi negozi_pkey; Type: CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.negozi
    ADD CONSTRAINT negozi_pkey PRIMARY KEY (id);


--
-- Name: notifiche notifiche_pkey; Type: CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.notifiche
    ADD CONSTRAINT notifiche_pkey PRIMARY KEY (id);


--
-- Name: offerte offerte_pkey; Type: CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.offerte
    ADD CONSTRAINT offerte_pkey PRIMARY KEY (id);


--
-- Name: preferiti preferiti_pkey; Type: CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.preferiti
    ADD CONSTRAINT preferiti_pkey PRIMARY KEY (id);


--
-- Name: preferiti preferiti_unici; Type: CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.preferiti
    ADD CONSTRAINT preferiti_unici UNIQUE (utente_id, negozio_id);


--
-- Name: segnalazioni segnalazioni_pkey; Type: CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.segnalazioni
    ADD CONSTRAINT segnalazioni_pkey PRIMARY KEY (id);


--
-- Name: tag_eventi tag_eventi_nome_key; Type: CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.tag_eventi
    ADD CONSTRAINT tag_eventi_nome_key UNIQUE (nome);


--
-- Name: tag_eventi tag_eventi_pkey; Type: CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.tag_eventi
    ADD CONSTRAINT tag_eventi_pkey PRIMARY KEY (id);


--
-- Name: utenti utenti_email_key; Type: CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.utenti
    ADD CONSTRAINT utenti_email_key UNIQUE (email);


--
-- Name: utenti utenti_pkey; Type: CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.utenti
    ADD CONSTRAINT utenti_pkey PRIMARY KEY (id);


--
-- Name: utenti_profili utenti_profili_pkey; Type: CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.utenti_profili
    ADD CONSTRAINT utenti_profili_pkey PRIMARY KEY (id);


--
-- Name: utenti_profili utenti_profili_utente_id_key; Type: CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.utenti_profili
    ADD CONSTRAINT utenti_profili_utente_id_key UNIQUE (utente_id);


--
-- Name: idx_eventi_posizione; Type: INDEX; Schema: public; Owner: mammopiga
--

CREATE INDEX idx_eventi_posizione ON public.eventi USING gist (posizione);


--
-- Name: idx_media_entita; Type: INDEX; Schema: public; Owner: mammopiga
--

CREATE INDEX idx_media_entita ON public.media USING btree (tipo_entita, entita_id);


--
-- Name: idx_negozi_posizione; Type: INDEX; Schema: public; Owner: mammopiga
--

CREATE INDEX idx_negozi_posizione ON public.negozi USING gist (posizione);


--
-- Name: idx_segnalazioni_posizione; Type: INDEX; Schema: public; Owner: mammopiga
--

CREATE INDEX idx_segnalazioni_posizione ON public.segnalazioni USING gist (posizione);


--
-- Name: eventi trigger_evento_approvato; Type: TRIGGER; Schema: public; Owner: mammopiga
--

CREATE TRIGGER trigger_evento_approvato AFTER UPDATE ON public.eventi FOR EACH ROW EXECUTE FUNCTION public.notifica_evento_approvato();


--
-- Name: eventi trigger_notifica_evento; Type: TRIGGER; Schema: public; Owner: mammopiga
--

CREATE TRIGGER trigger_notifica_evento AFTER UPDATE ON public.eventi FOR EACH ROW EXECUTE FUNCTION public.crea_notifica_evento();


--
-- Name: citta citta_cliente_fk; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.citta
    ADD CONSTRAINT citta_cliente_fk FOREIGN KEY (cliente_id) REFERENCES public.clienti(id);


--
-- Name: comunicazioni_led comunicazioni_citta_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.comunicazioni_led
    ADD CONSTRAINT comunicazioni_citta_fk FOREIGN KEY (citta_id) REFERENCES public.citta(id);


--
-- Name: eventi eventi_admin_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.eventi
    ADD CONSTRAINT eventi_admin_fk FOREIGN KEY (approvato_da) REFERENCES public.utenti(id) ON DELETE SET NULL;


--
-- Name: eventi eventi_citta_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.eventi
    ADD CONSTRAINT eventi_citta_fk FOREIGN KEY (citta_id) REFERENCES public.citta(id);


--
-- Name: eventi eventi_creatore_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.eventi
    ADD CONSTRAINT eventi_creatore_fk FOREIGN KEY (creato_da) REFERENCES public.utenti(id);


--
-- Name: eventi_immagini eventi_immagini_evento_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.eventi_immagini
    ADD CONSTRAINT eventi_immagini_evento_fk FOREIGN KEY (evento_id) REFERENCES public.eventi(id) ON DELETE CASCADE;


--
-- Name: eventi_immagini eventi_immagini_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.eventi_immagini
    ADD CONSTRAINT eventi_immagini_fk FOREIGN KEY (evento_id) REFERENCES public.eventi(id) ON DELETE CASCADE;


--
-- Name: eventi eventi_negozio_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.eventi
    ADD CONSTRAINT eventi_negozio_fk FOREIGN KEY (negozio_id) REFERENCES public.negozi(id);


--
-- Name: eventi_preferiti eventi_pref_evento_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.eventi_preferiti
    ADD CONSTRAINT eventi_pref_evento_fk FOREIGN KEY (evento_id) REFERENCES public.eventi(id) ON DELETE CASCADE;


--
-- Name: eventi_preferiti eventi_pref_utente_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.eventi_preferiti
    ADD CONSTRAINT eventi_pref_utente_fk FOREIGN KEY (utente_id) REFERENCES public.utenti(id) ON DELETE CASCADE;


--
-- Name: eventi_tag eventi_tag_evento_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.eventi_tag
    ADD CONSTRAINT eventi_tag_evento_fk FOREIGN KEY (evento_id) REFERENCES public.eventi(id) ON DELETE CASCADE;


--
-- Name: eventi_tag eventi_tag_tag_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.eventi_tag
    ADD CONSTRAINT eventi_tag_tag_fk FOREIGN KEY (tag_id) REFERENCES public.tag_eventi(id) ON DELETE CASCADE;


--
-- Name: negozi negozi_categoria_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.negozi
    ADD CONSTRAINT negozi_categoria_fk FOREIGN KEY (categoria_id) REFERENCES public.categorie(id);


--
-- Name: negozi negozi_citta_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.negozi
    ADD CONSTRAINT negozi_citta_fk FOREIGN KEY (citta_id) REFERENCES public.citta(id);


--
-- Name: negozi negozi_creatore_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.negozi
    ADD CONSTRAINT negozi_creatore_fk FOREIGN KEY (creato_da) REFERENCES public.utenti(id);


--
-- Name: negozi_immagini negozi_immagini_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.negozi_immagini
    ADD CONSTRAINT negozi_immagini_fk FOREIGN KEY (negozio_id) REFERENCES public.negozi(id) ON DELETE CASCADE;


--
-- Name: negozi negozi_proprietario_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.negozi
    ADD CONSTRAINT negozi_proprietario_fk FOREIGN KEY (proprietario_id) REFERENCES public.utenti(id) ON DELETE SET NULL;


--
-- Name: notifiche notifiche_utente_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.notifiche
    ADD CONSTRAINT notifiche_utente_fk FOREIGN KEY (utente_id) REFERENCES public.utenti(id) ON DELETE CASCADE;


--
-- Name: offerte offerte_citta_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.offerte
    ADD CONSTRAINT offerte_citta_fk FOREIGN KEY (citta_id) REFERENCES public.citta(id);


--
-- Name: offerte offerte_negozio_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.offerte
    ADD CONSTRAINT offerte_negozio_fk FOREIGN KEY (negozio_id) REFERENCES public.negozi(id) ON DELETE CASCADE;


--
-- Name: preferiti preferiti_negozio_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.preferiti
    ADD CONSTRAINT preferiti_negozio_fk FOREIGN KEY (negozio_id) REFERENCES public.negozi(id) ON DELETE CASCADE;


--
-- Name: preferiti preferiti_utente_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.preferiti
    ADD CONSTRAINT preferiti_utente_fk FOREIGN KEY (utente_id) REFERENCES public.utenti(id) ON DELETE CASCADE;


--
-- Name: segnalazioni segnalazioni_citta_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.segnalazioni
    ADD CONSTRAINT segnalazioni_citta_fk FOREIGN KEY (citta_id) REFERENCES public.citta(id);


--
-- Name: segnalazioni segnalazioni_utente_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.segnalazioni
    ADD CONSTRAINT segnalazioni_utente_fk FOREIGN KEY (utente_id) REFERENCES public.utenti(id) ON DELETE SET NULL;


--
-- Name: utenti_profili utenti_profili_fk; Type: FK CONSTRAINT; Schema: public; Owner: mammopiga
--

ALTER TABLE ONLY public.utenti_profili
    ADD CONSTRAINT utenti_profili_fk FOREIGN KEY (utente_id) REFERENCES public.utenti(id) ON DELETE CASCADE;


--
-- Name: SCHEMA api; Type: ACL; Schema: -; Owner: mammopiga
--

GRANT USAGE ON SCHEMA api TO api_anon;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO api_anon;


--
-- Name: FUNCTION eventi_vicini(lat double precision, lon double precision, raggio integer); Type: ACL; Schema: api; Owner: mammopiga
--

GRANT ALL ON FUNCTION api.eventi_vicini(lat double precision, lon double precision, raggio integer) TO api_anon;


--
-- Name: FUNCTION home(); Type: ACL; Schema: api; Owner: postgres
--

GRANT ALL ON FUNCTION api.home() TO api_anon;


--
-- Name: FUNCTION mappa_citta(); Type: ACL; Schema: api; Owner: mammopiga
--

GRANT ALL ON FUNCTION api.mappa_citta() TO api_anon;


--
-- Name: TABLE eventi; Type: ACL; Schema: public; Owner: mammopiga
--

GRANT SELECT ON TABLE public.eventi TO api_anon;


--
-- Name: TABLE negozi; Type: ACL; Schema: public; Owner: mammopiga
--

GRANT SELECT ON TABLE public.negozi TO api_anon;


--
-- Name: TABLE api_eventi_pubblici; Type: ACL; Schema: api; Owner: mammopiga
--

GRANT SELECT ON TABLE api.api_eventi_pubblici TO api_anon;


--
-- Name: TABLE comunicazioni_led; Type: ACL; Schema: public; Owner: mammopiga
--

GRANT SELECT ON TABLE public.comunicazioni_led TO api_anon;


--
-- Name: TABLE offerte; Type: ACL; Schema: public; Owner: mammopiga
--

GRANT SELECT ON TABLE public.offerte TO api_anon;


--
-- Name: TABLE api_home; Type: ACL; Schema: api; Owner: mammopiga
--

GRANT SELECT ON TABLE api.api_home TO api_anon;


--
-- Name: TABLE segnalazioni; Type: ACL; Schema: public; Owner: mammopiga
--

GRANT SELECT ON TABLE public.segnalazioni TO api_anon;


--
-- Name: TABLE api_mappa; Type: ACL; Schema: api; Owner: mammopiga
--

GRANT SELECT ON TABLE api.api_mappa TO api_anon;


--
-- Name: TABLE eventi_home; Type: ACL; Schema: api; Owner: mammopiga
--

GRANT SELECT ON TABLE api.eventi_home TO api_anon;


--
-- Name: TABLE eventi_pubblici; Type: ACL; Schema: api; Owner: mammopiga
--

GRANT SELECT ON TABLE api.eventi_pubblici TO api_anon;


--
-- Name: TABLE negozi; Type: ACL; Schema: api; Owner: mammopiga
--

GRANT SELECT ON TABLE api.negozi TO api_anon;


--
-- Name: TABLE notifiche; Type: ACL; Schema: api; Owner: mammopiga
--

GRANT SELECT ON TABLE api.notifiche TO api_anon;


--
-- Name: TABLE offerte_attive; Type: ACL; Schema: api; Owner: mammopiga
--

GRANT SELECT ON TABLE api.offerte_attive TO api_anon;


--
-- Name: TABLE view_comunicazioni_led; Type: ACL; Schema: api; Owner: mammopiga
--

GRANT SELECT ON TABLE api.view_comunicazioni_led TO api_anon;


--
-- Name: TABLE view_eventi_dettaglio; Type: ACL; Schema: api; Owner: mammopiga
--

GRANT SELECT ON TABLE api.view_eventi_dettaglio TO api_anon;


--
-- Name: TABLE view_eventi_home; Type: ACL; Schema: api; Owner: mammopiga
--

GRANT SELECT ON TABLE api.view_eventi_home TO api_anon;


--
-- Name: TABLE view_negozi; Type: ACL; Schema: api; Owner: mammopiga
--

GRANT SELECT ON TABLE api.view_negozi TO api_anon;


--
-- Name: TABLE view_notifiche; Type: ACL; Schema: api; Owner: mammopiga
--

GRANT SELECT ON TABLE api.view_notifiche TO api_anon;


--
-- Name: TABLE view_offerte_attive; Type: ACL; Schema: api; Owner: mammopiga
--

GRANT SELECT ON TABLE api.view_offerte_attive TO api_anon;


--
-- Name: TABLE view_segnalazioni_mappa; Type: ACL; Schema: api; Owner: mammopiga
--

GRANT SELECT ON TABLE api.view_segnalazioni_mappa TO api_anon;


--
-- Name: TABLE api_eventi_pubblici; Type: ACL; Schema: public; Owner: mammopiga
--

GRANT SELECT ON TABLE public.api_eventi_pubblici TO api_anon;


--
-- PostgreSQL database dump complete
--

\unrestrict TiMKx0Q7l5uGoimJhw5I9geyQ75fETgJ3HVASgkmC0cbhsC16U5z2JdukQMSVIz

