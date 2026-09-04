-- ============================================================
-- 03 — Classificação das administradoras
-- ============================================================
-- Critério do autor, não do Banco Central. Existe para permitir
-- comparar exclusão e inadimplência entre modelos de negócio.
--
-- Mapeamento por NOME EXATO. Padrão de texto (ILIKE) erra:
-- '%PORTO%' captura Porto Seguro e Portobens, empresas
-- diferentes. Este arquivo é o ÚNICO lugar onde a
-- classificação é definida — para mudar, edite a lista abaixo.
--
-- Pode ser rodado quantas vezes quiser: zera antes de aplicar.
-- ============================================================

SET search_path TO consorcio, public;

ALTER TABLE dim_administradora
    DROP CONSTRAINT IF EXISTS dim_administradora_tipo_administradora_check;

ALTER TABLE dim_administradora
    ADD CONSTRAINT dim_administradora_tipo_administradora_check
    CHECK (tipo_administradora IN
          ('Cooperativa','Banco','Montadora','Máquinas e Implementos',
           'Varejo','Concessionária','Independente','Outros','Não classificada'));

UPDATE dim_administradora SET tipo_administradora = 'Não classificada';

UPDATE dim_administradora a
   SET tipo_administradora = m.tipo
  FROM (VALUES
    -- ---------- Cooperativa ----------
    ('ADM CONS SICREDI LTDA',                  'Cooperativa'),
    ('SICOOB ADM CONS LTDA.',                  'Cooperativa'),
    ('ADM CONS UNICOOB LTDA',                  'Cooperativa'),

    -- ---------- Banco ----------
    ('BB CONSÓRCIOS',                          'Banco'),
    ('BRADESCO CONS. LTDA.',                   'Banco'),
    ('ITAÚ ADM DE CONSÓRCIOS LTDA',            'Banco'),
    ('ITAÚ UNIBANCO VEÍCULOS ADM CONS LTDA.',  'Banco'),
    ('SANTANDER BRASIL ADM CONS LTDA',         'Banco'),
    ('BANRISUL S.A. ADM CONSÓRCIOS',           'Banco'),
    ('PORTO SEGURO ADM. CONS. LTDA',           'Banco'),  -- Porto Bank
    ('BBC ADM CONS LTDA.',                     'Banco'),

    -- ---------- Montadora ----------
    ('ADM CONS NAC HONDA LTDA',                'Montadora'),
    ('YAMAHA ADM CONS LTDA',                   'Montadora'),
    ('SUZUKI MOTOS ADM. CONS. LTDA',           'Montadora'),
    ('CONS. NACIONAL VOLKSWAGEN LTDA.',        'Montadora'),
    ('TOYOTA ADM CONS BRASIL LTDA.',           'Montadora'),
    ('CONSORCIO VOLVO',                        'Montadora'),
    ('SCANIA ADM CONS LTDA.',                  'Montadora'),
    ('ADM CONS RCI BRASIL LTDA',               'Montadora'),  -- Renault
    ('GMAC ADM CONS  LTDA',                    'Montadora'),  -- GM

    -- ---------- Máquinas e Implementos ----------
    ('RANDON ADM CONSÓRCIOS LTDA.',            'Máquinas e Implementos'),
    ('MASSEY FERGUSON ADM DE CONS LTDA',       'Máquinas e Implementos'),
    ('VALTRA ADM CONS LTDA',                   'Máquinas e Implementos'),
    ('BAMAQ ADM CONS LTDA',                    'Máquinas e Implementos'),

    -- ---------- Varejo ----------
    -- Cota vendida no balcão, junto da compra do bem.
    ('CONSORCIO GAZIN',                        'Varejo'),
    ('LUIZA ADM. CONS. LTDA',                  'Varejo'),

    -- ---------- Concessionária ----------
    -- Grupos de revenda com consórcio próprio.
    -- Só estes dois confirmados. Para incluir candidatos
    -- (Comauto, Fancar, Camvel, Francauto, Menegalli,
    -- Carlessi, Breitkopf, Sponchiado, Gambatto, Motoasa),
    -- confirme antes e acrescente aqui.
    ('RODOBENS ADM CONSORCIOS LTDA',           'Concessionária'),
    ('FIPAL',                                  'Concessionária'),

    -- ---------- Independente (maior porte) ----------
    ('ADEMICON ADM CONS S.A.',                 'Independente'),
    ('HS ADM CONS S.A.',                       'Independente'),
    ('EMBRACON ADM CONS S.A.',                 'Independente'),
    ('XS5 ADM CONS S.A.',                      'Independente'),
    ('ÂNCORA ADM CONS S.A.',                   'Independente'),
    ('CANOPUS ADM CONSÓRCIOS',                 'Independente'),
    ('MYCON ADM CONS  S.A.',                   'Independente'),
    ('KLUBI',                                  'Independente'),
    ('DISAL  ADM CONS LTDA',                   'Independente'),  -- REVISAR: 149k cotas
    ('CNP CONSORCIO S.A. ADM CONS',            'Independente'),
    ('BR CONSÓRCIOS ADM. CONS. LTDA.',         'Independente'),
    ('MAGGI ADM CONS LTDA',                    'Independente'),
    ('UNIFISA ADM NAC CONS LTDA',              'Independente'),
    ('MULTIMARCAS ADM.CONS.LTDA.',             'Independente'),
    ('RECON ADM. DE CONSORCIOS LTDA',          'Independente'),

    -- ---------- Outros ----------
    -- Associações de classe, clubes e fundações.
    ('FUNDACAO HAB. DO EXERCITO-FHE',          'Outros'),
    ('BANCORBRÁS',                             'Outros'),
    ('CLUBE NAVAL',                            'Outros'),
    ('ASSOC DOS JUIZES DO RS',                 'Outros'),
    ('UNAFISCO-ASS NAC AUD FISC RFB',          'Outros'),
    ('ASSOC BAHIANA DE MEDICINA ABM',          'Outros'),
    ('FED.NAC.ASSOC.SERV.BCO CENTRAL',         'Outros'),
    ('COOPERATIVA MISTA ROMA (EX-JOCKEY',      'Outros')
  ) AS m(nome, tipo)
 WHERE a.nome_administradora = m.nome;

-- Cauda longa: pequenas e regionais, sem vínculo identificado.
UPDATE dim_administradora SET tipo_administradora = 'Independente'
 WHERE tipo_administradora = 'Não classificada';


-- ------------------------------------------------------------
-- Conferência
-- ------------------------------------------------------------
-- count(DISTINCT) é obrigatório: contar linhas do fato daria
-- administradora × segmento, não administradoras.
SELECT a.tipo_administradora,
       count(DISTINCT a.cnpj_administradora) AS administradoras,
       sum(f.cotas_ativas)                   AS cotas_ativas,
       round(100.0 * sum(f.cotas_ativas)
             / sum(sum(f.cotas_ativas)) OVER (), 1) AS pct_mercado
  FROM dim_administradora a
  JOIN fato_segmento_mensal f USING (cnpj_administradora)
 GROUP BY 1
 ORDER BY cotas_ativas DESC;

-- Nome errado no mapeamento cai silenciosamente em Independente.
-- Confira as maiores que ficaram nessa categoria:
-- SELECT a.nome_administradora, sum(f.cotas_ativas) AS cotas
--   FROM dim_administradora a
--   JOIN fato_segmento_mensal f USING (cnpj_administradora)
--  WHERE a.tipo_administradora = 'Independente'
--  GROUP BY 1 ORDER BY cotas DESC LIMIT 20;
