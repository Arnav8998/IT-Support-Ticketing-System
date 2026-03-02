const express = require("express");

module.exports = (getPool, sql) => {
  const router = express.Router();

  // POST /api/tickets  -> support.sp_CreateTicket
  router.post("/tickets", async (req, res) => {
    try {
      const {
        createdByUserId,
        guildId,
        channelId,
        tier = 1,
        title = null,
        initialMessage = null,
      } = req.body;

      // Basic validation
      if (!createdByUserId || !guildId || !channelId) {
        return res.status(400).json({
          error: "createdByUserId, guildId, and channelId are required",
        });
      }

      const pool = await getPool();

      const request = pool.request();
      request.input("CreatedByUserID", sql.BigInt, createdByUserId);
      request.input("GuildID", sql.BigInt, guildId);
      request.input("ChannelID", sql.BigInt, channelId);
      request.input("Tier", sql.TinyInt, tier);
      request.input("Title", sql.NVarChar(200), title);
      request.input("InitialMessage", sql.NVarChar(sql.MAX), initialMessage);

      request.output("NewTicketID", sql.BigInt);

      await request.execute("support.sp_CreateTicket");

      res.status(201).json({
        message: "Ticket created",
        ticketId: request.parameters.NewTicketID.value,
      });
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  return router;
};
