-- ============================================================
-- Projeto: Índice de Exclusão do Sistema de Consórcios (BCB)
-- Banco: PostgreSQL 16
-- Fonte: BCB, "Dados Consolidados" > "Segmentos Consolidados"
-- Layout confirmado na data-base 202606: 19 colunas, ';', WIN1252
-- ============================================================

CREATE SCHEMA IF NOT EXISTS consorcio;
SET search_path TO consorcio, public;


-- ------------------------------------------------------------
-- 1. STAGING — espelho fiel do arquivo, tudo text
-- ------------------------------------------------------------
-- Ordem idêntica à do CSV. Não reordenar: o \copy carrega por
-- posição, não por nome.

DROP TABLE IF EXISTS stg_segmentos;

CREATE TABLE stg_segmentos (
    nome_administradora              text,  -- 1
    cnpj_administradora              text,  -- 2  (raiz, 8 dígitos)
    data_base                        text,  -- 3  AAAAMM
    codigo_segmento                  text,  -- 4
    taxa_administracao               text,  -- 5  decimal com vírgula
    grupos_ativos                    text,  -- 6
    grupos_constituidos_mes          text,  -- 7
    grupos_encerrados_mes            text,  -- 8
    cotas_comercializadas_mes        text,  -- 9
    cotas_excluidas_a_comercializar  text,  -- 10
    cotas_ativas_contempladas        text,  -- 11 acumulado
    cotas_ativas_nao_contempladas    text,  -- 12
    cotas_contempladas_mes           text,  -- 13
    cotas_ativas_em_dia              text,  -- 14
    cotas_contempladas_inadimpl      text,  -- 15
    cotas_nao_contempladas_inadimpl  text,  -- 16
    cotas_excluidas                  text,  -- 17
    cotas_ativas_quitadas            text,  -- 18
    cotas_credito_pendente           text   -- 19
);


-- ------------------------------------------------------------
-- 2. DIMENSÃO DE SEGMENTO
-- ------------------------------------------------------------
DROP TABLE IF EXISTS dim_segmento CASCADE;

CREATE TABLE dim_segmento (
    codigo_segmento   smallint PRIMARY KEY,
    descricao         text NOT NULL,
    grupo_bem         text NOT NULL
);

INSERT INTO dim_segmento VALUES
    (1, 'Bens imóveis',                                                'Imóveis'),
    (2, 'Tratores, máquinas agrícolas, embarcações e veículos de carga','Móveis'),
    (3, 'Veículos automotores não incluídos no segmento 2',             'Móveis'),
    (4, 'Motocicletas e motonetas',                                    'Móveis'),
    (5, 'Outros bens móveis duráveis',                                 'Móveis'),
    (6, 'Serviços',                                                    'Serviços');
-- Conferir a descrição do segmento 6 no "Significado dos campos".


-- ------------------------------------------------------------
-- 3. DIMENSÃO DE ADMINISTRADORA
-- ------------------------------------------------------------
-- tipo_administradora é classificação SUA, não do BCB.
DROP TABLE IF EXISTS dim_administradora CASCADE;

CREATE TABLE dim_administradora (
    cnpj_administradora   text PRIMARY KEY,
    nome_administradora   text NOT NULL,
    tipo_administradora   text
        DEFAULT 'Não classificada'
        CHECK (tipo_administradora IN
              ('Cooperativa','Banco','Montadora','Máquinas e Implementos',
               'Varejo','Concessionária','Independente','Outros','Não classificada'))
);


-- ------------------------------------------------------------
-- 4. FATO
-- ------------------------------------------------------------
DROP TABLE IF EXISTS fato_segmento_mensal;

CREATE TABLE fato_segmento_mensal (
    data_base                        date     NOT NULL,
    cnpj_administradora              text     NOT NULL REFERENCES dim_administradora,
    codigo_segmento                  smallint NOT NULL REFERENCES dim_segmento,

    taxa_administracao               numeric(10,5),

    grupos_ativos                    integer,
    grupos_constituidos_mes          integer,
    grupos_encerrados_mes            integer,

    cotas_comercializadas_mes        integer,
    cotas_excluidas_a_comercializar  integer,
    cotas_ativas_contempladas        integer,
    cotas_ativas_nao_contempladas    integer,
    cotas_contempladas_mes           integer,
    cotas_ativas_em_dia              integer,
    cotas_contempladas_inadimpl      integer,
    cotas_nao_contempladas_inadimpl  integer,
    cotas_excluidas                  integer,
    cotas_ativas_quitadas            integer,
    cotas_credito_pendente           integer,

    -- Coluna calculada pelo banco: não existe no arquivo.
    -- O total de cotas ativas é a soma de contempladas e não
    -- contempladas. Deixar o Postgres calcular evita que a
    -- soma seja escrita de um jeito em cada consulta.
    cotas_ativas integer GENERATED ALWAYS AS
        (coalesce(cotas_ativas_contempladas,0)
       + coalesce(cotas_ativas_nao_contempladas,0)) STORED,

    PRIMARY KEY (data_base, cnpj_administradora, codigo_segmento)
);

CREATE INDEX idx_fato_data_base ON fato_segmento_mensal (data_base);
CREATE INDEX idx_fato_segmento  ON fato_segmento_mensal (codigo_segmento);
