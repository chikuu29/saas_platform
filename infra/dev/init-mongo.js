db = db.getSiblingDB("workspace_db");

db.createCollection("app_health");
db.app_health.updateOne(
  { name: "workspace" },
  {
    $set: {
      name: "workspace",
      initializedAt: new Date(),
      status: "ready"
    }
  },
  { upsert: true }
);

