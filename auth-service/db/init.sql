CREATE TABLE IF NOT EXISTS api_keys (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    
    -- key_hash armazena o hash SHA-256 da chave, que tem 64 caracteres hexadecimais
    key_hash VARCHAR(64) NOT NULL UNIQUE, 
    
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Chave de serviço para comunicação interna (apenas dev local)
INSERT INTO api_keys (name, key_hash) VALUES ('internal-service', '9bb2f35b2574e42a2e775bfe6881ef5950b31f3bdd918c3590dfc0ef24fda70f')
ON CONFLICT (key_hash) DO NOTHING;