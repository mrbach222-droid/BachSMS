PRAGMA foreign_keys = ON;
CREATE TABLE IF NOT EXISTS channels (
 id TEXT PRIMARY KEY, label TEXT NOT NULL, writer_hash TEXT NOT NULL UNIQUE,
 reader_hash TEXT NOT NULL UNIQUE, created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS batches (
 channel TEXT NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
 id TEXT NOT NULL, digest TEXT NOT NULL, created_at INTEGER NOT NULL,
 PRIMARY KEY(channel,id)
);
CREATE TABLE IF NOT EXISTS jobs (
 channel TEXT NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
 id TEXT NOT NULL, batch_id TEXT NOT NULL, digest TEXT NOT NULL,
 payload TEXT, created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL,
 received_at INTEGER, status TEXT NOT NULL DEFAULT 'pending',
 PRIMARY KEY(channel,id)
);
CREATE INDEX IF NOT EXISTS jobs_pending ON jobs(channel,received_at,created_at,id);
CREATE TABLE IF NOT EXISTS events (
 channel TEXT NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
 id TEXT NOT NULL, job_id TEXT NOT NULL, status TEXT NOT NULL, occurred_at TEXT NOT NULL,
 created_at INTEGER NOT NULL, PRIMARY KEY(channel,id)
);
