require("dotenv").config();
const app = require("./app");
const { getPool } = require("./config/db");

const PORT = process.env.PORT || 3000;

async function start() {
  try {
    await getPool();
    console.log("Connected to SQL Server");

    app.listen(PORT, () => {
      console.log(`Server running on port ${PORT}`);
    });
  } catch (err) {
    console.error("Startup failed:", err.message);
    process.exit(1);
  }
}

start();
