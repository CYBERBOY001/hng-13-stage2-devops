const express = require('express');
const app = express();
const port = process.env.PORT || 8080;

// Middleware to parse JSON and URL-encoded bodies
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Global chaos state
let chaosMode = null; // null, 'error', or 'timeout'

// Chaos endpoints
app.post('/chaos/start', (req, res) => {
  const { mode } = req.query;
  if (mode === 'error' || mode === 'timeout') {
    chaosMode = mode;
    console.log(`Chaos mode activated: ${mode}`);
    res.status(200).json({ status: 'chaos started', mode });
  } else {
    res.status(400).json({ error: 'Invalid mode. Use "error" or "timeout"' });
  }
});

app.post('/chaos/stop', (req, res) => {
  chaosMode = null;
  console.log('Chaos mode deactivated');
  res.status(200).json({ status: 'chaos stopped' });
});

// Health check endpoint
app.get('/healthz', (req, res) => {
  // Apply chaos if active
  if (chaosMode === 'error') {
    return res.status(500).json({ error: 'Chaos: Simulated error' });
  } else if (chaosMode === 'timeout') {
    // Simulate timeout by delaying indefinitely (or long enough to trigger proxy timeout)
    return setTimeout(() => {
      res.status(200).json({ status: 'healthy' });
    }, 30000); // 30s delay to ensure proxy timeout
  }
  res.status(200).json({ status: 'healthy' });
});

// Version endpoint
app.get('/version', (req, res) => {
  // Apply chaos if active
  if (chaosMode === 'error') {
    return res.status(500).json({ error: 'Chaos: Simulated error' });
  } else if (chaosMode === 'timeout') {
    // Simulate timeout
    return setTimeout(() => {
      res.json({
        app: process.env.APP_POOL || 'unknown',
        release: process.env.RELEASE_ID || 'unknown',
        timestamp: new Date().toISOString()
      });
    }, 30000);
  }

  // Normal response
  res.set({
    'X-App-Pool': process.env.APP_POOL || 'unknown',
    'X-Release-Id': process.env.RELEASE_ID || 'unknown'
  });
  res.json({
    app: process.env.APP_POOL || 'unknown',
    release: process.env.RELEASE_ID || 'unknown',
    timestamp: new Date().toISOString()
  });
});

// Catch-all for other routes (optional, return 404)
app.use((req, res) => {
  res.status(404).json({ error: 'Not found' });
});

app.listen(port, () => {
  console.log(`App listening on port ${port}`);
  console.log(`APP_POOL: ${process.env.APP_POOL}`);
  console.log(`RELEASE_ID: ${process.env.RELEASE_ID}`);
});

module.exports = app;