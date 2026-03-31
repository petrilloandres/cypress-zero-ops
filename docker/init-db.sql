-- =============================================================================
-- Cypress Zero-Ops — PostgreSQL Init Script
-- =============================================================================
-- Creates separate logical databases for each service that shares the main
-- PostgreSQL instance. Runs automatically on first container start.
-- =============================================================================

-- Phase 1
CREATE DATABASE logto;
CREATE DATABASE n8n;

-- Phase 2
CREATE DATABASE docuseal;

-- Phase 3
CREATE DATABASE twenty;
