--liquibase formatted sql

--changeset telemed:004-seed-additional-specialties
INSERT INTO specialties (name, description)
VALUES
    ('Neurología', 'Atención de enfermedades y trastornos del sistema nervioso.'),
    ('Ginecología', 'Atención de la salud del sistema reproductivo femenino.'),
    ('Ortopedia', 'Atención de enfermedades y lesiones del sistema musculoesquelético.')
ON CONFLICT (name) DO NOTHING;
