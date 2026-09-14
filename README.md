# DSA-Assignment1

Distributed Library & Rental Systems
DSA612S — Distributed Systems and Applications, NUST Due: 14 Sept 2026, 23:59 · Team: 8
Two independent Ballerina systems in one repo:
Q1 — Library & Resource Management System (REST) — 50 marks
Q2 — Rental Accommodation System (gRPC) — 50 marks
Tasks
Q1: models & storage → asset CRUD → maintenance/schedules → work orders + CLI client Q2: .proto + skeleton → host logic (add/update/remove property, create_users) → guest logic (list/search/book/confirm) → gRPC client
Models (Q1) and proto (Q2) go first and merge to main first — everything else builds on them.

Structure
question1-library-system/
├── service/    # REST API + modules (models, assets, maintenance, workorders)
├── client/     # CLI client
└── docs/

question2-accommodation-system/
├── proto/      # rental.proto
├── server/     # host + guest logic
└── client/


Each service//client/ folder needs its own Ballerina.toml.
.gitignore
target/, generated/, Config.toml, .idea/, *.iml, .vscode/, .DS_Store

Git Workflow
git checkout -b feature/q1-asset-crud   # branch per task
git commit -m "feat(q1): add asset CRUD"
git push origin feature/q1-asset-crud   # PR into main, get it reviewed
git pull origin main                    # before every session
