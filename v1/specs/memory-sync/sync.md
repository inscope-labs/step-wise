# Spec: Memory Synchronization

| | |
|---|---|
| Framework | 1.6.1 (unreleased) |
| Component | spec `memory-sync/sync` |
| Version | 1.6.1-dev |
| Parent feature | `feature:memory-sync` |
| Supersedes | nothing |
| Status | Draft. Loaded on demand. |

How two or more machines converge on the same memory with no server, no coordinator, and no merge conflicts. Record format: `memory-sync/schema`.

## 1. The model

The store is a **grow-only set of immutable records**. The current memory is a *view* computed from that set. Merging two stores is set union by `id`, so it is commutative, associative and idempotent. Copying files in any order, any number of times, gives the same result.

## 2. One writer per file

- `replicas/<replica>.jsonl` is appended to **only** by the replica it is named for.
- `imports/<hash>.jsonl` is immutable, named by the hash of its content.

So a file-level sync tool never has two machines editing the same file. There is nothing to merge inside a file, which is why plain git, rsync, Syncthing or a cloud folder all work.

## 3. Replica identity

Each machine has one replica id per store (8 hex characters), kept in local state, never synced. `rotate-replica` issues a new id. A store copied wholesale *with its local state* would give two machines one id. `status` detects that (section 5), and `rotate-replica` fixes it.

## 4. Writing

1. Take an exclusive lock on the replica file.
2. Check the file has not regressed (section 5). If it has, refuse to write.
3. Compute the clock (below) and `prev` (the last complete record in this file).
4. Append the record as **one line with its newline, in one write**.
5. Release the lock and update local state.

By default a new `put` also lists, in `supersedes`, every visible record with the same group key that this replica can see. Concurrent writers on other replicas cannot see each other, so their records do not supersede each other and are reported as `disputed`.

**Hybrid logical clock.** `t` is milliseconds and `c` a counter. A write uses `t = max(now, latest t in the store)`. If that `t` equals the latest, `c` is the latest `c` plus one, else `c = 0`. This keeps causality (a write made after a sync sorts after what it saw) even when clocks disagree. Total order is `(t, c, replica)`.

## 5. Reading and integrity

The reader takes the union of every file and **drops**, counting each:

- a **torn** final line (no trailing newline, as when a sync tool copies mid-append). It completes on the next sync
- an **invalid** line: unparseable or failing the schema
- a **tampered** record: its `id` does not match its content
- an **unsupported** record: `v` newer than the reader knows

It **reports** without dropping:

- **chain breaks**: a record's `prev` is not the record before it in its file (something was removed or reordered)
- **forks**: two records from one replica share a `prev` (two machines used one replica id)
- **regression**: this machine last wrote more than the file now holds (a sync tool restored an older copy). Writes are refused until the file is restored or the replica is rotated, so an old copy cannot silently fork history

Integrity checks detect corruption and rollback. They do not authenticate writers (section 8).

## 6. The view

Records are grouped by `(kind, project, host, subject)`.

1. **Hidden**: any record named in another record's `supersedes`, or in a `retract` record's `retracts`.
2. **Retract wins**, regardless of clock. A retraction is permanent, so withdrawing a mistaken record cannot be undone by an old copy arriving later. Correcting it means writing a new record.
3. **Suspect**: a record with `t` more than 24 hours after the reader's clock. It can neither win, advance the clock, nor hide other records (its `supersedes` and `retracts` are ignored) until its time arrives, so one wrong or malicious timestamp cannot pin or erase a subject. It stays stored and is reported.
4. Among what remains, the winner has the greatest `(t, c, replica)`. If **more than one** remains, the group is `disputed`. All alternatives are returned, and the reader must re-verify rather than trust either.

For a fixed set of records, clock and host, the view is identical on every machine. Two machines always agree on **which records are visible and which subjects are disputed**. A status that depends on the reader (a fact recorded on another host is `other-host` there and `unverified` where it was written) is relative to the reader's host by design.

## 7. Transports

| Transport | How |
|---|---|
| git | commit `replicas/` and `imports/`, pull, push. Add nothing else. Local state is elsewhere |
| rsync, Syncthing, a cloud folder | sync the store directory as it is |
| a copied file | `export` to a JSONL bundle, move it however you like, `import` it on the other side |

`import` validates each line, drops bad ones, and stores the rest as `imports/<hash>.jsonl`. Importing the same bundle twice changes nothing. After any sync, run `status` (integrity) and then `verify` (freshness of what you now hold). Facts recorded on another host show as `other-host` until re-checked here.

## 8. Guarantees and non-guarantees

**Guaranteed:** convergence of the view; no write conflicts; idempotent merges; detection of torn writes, corruption, rollback and replica-id reuse.

**Not guaranteed:**

- **Authentication.** The trust boundary is whoever can write into the store's files. A hostile writer can add records. The defenses are that memory only guides and never authorizes (see `memory-sync/safety`), and that the operator confirms what shapes a plan.
- **Erasure.** Retraction hides a record; it does not remove it from disks. Removing one means deleting its line from every replica and import file everywhere. A leaked secret also needs rotating.
- **Compaction.** The store only grows. A local index can be rebuilt at any time and is never synced.
