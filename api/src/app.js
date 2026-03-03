const express = require("express");
const ticketsRoutes = require("./routes/tickets.routes");

const app = express();
app.use(express.json());

app.get("/", (req, res) => {
  res.json({ message: "IT Support Ticketing API running" });
});

// API routes
app.use("/api/tickets", ticketsRoutes);

module.exports = app;
