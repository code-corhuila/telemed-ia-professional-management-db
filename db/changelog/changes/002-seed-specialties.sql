--liquibase formatted sql

--changeset telemed:002-seed-specialties
INSERT INTO specialties (name, description)
VALUES
    ('Medicina General', 'Atención médica general y orientación inicial.'),
    ('Pediatría', 'Atención integral de población pediátrica.'),
    ('Dermatología', 'Atención de enfermedades de piel, cabello y uñas.'),
    ('Cardiología', 'Atención de enfermedades cardiovasculares.')
ON CONFLICT (name) DO NOTHING;
