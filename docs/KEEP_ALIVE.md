# Preventing Render Cold Starts

Render free tier sleeps after ~15 minutes of inactivity. When a user hits the app,
it takes 30-60 seconds to wake up. Here's how to fix that.

## Quick Fix: Free Cron Ping (2 minutes)

1. Go to [cron-job.org](https://cron-job.org) (free, no credit card)
2. Sign up
3. Create a new job:
   - **URL:** `https://personal-os-prg4.onrender.com/api/health`
   - **Schedule:** Every 5 minutes
   - **Request method:** GET
4. Save and enable

That's it. The ping keeps your Render instance awake 24/7. Free forever.

## Better Fix: Migrate to Railway (no cold starts ever)

Railway has a $5/mo hobby plan with **zero cold starts**. Migration:

1. Sign up at [railway.app](https://railway.app)
2. Connect your GitHub repo
3. Set environment variables:
   - `GEMINI_API_KEY`
   - `GOOGLE_APPLICATION_CREDENTIALS` (upload the JSON file)
4. Railway auto-detects Python/Flask
5. Update `lib/services/api/api_service.dart`:
   ```dart
   static String baseUrl = 'https://your-app.up.railway.app';
   ```
6. Deploy

Railway is faster, more reliable, and $5/mo is worth it for a real app.

## Best Fix: Google Cloud Run (free tier, no cold starts)

Since you're already on Firebase (Google ecosystem), Cloud Run is the natural home.
Free tier gives you 240,000 vCPU-seconds/month — more than enough for a personal app.

1. Install `gcloud` CLI
2. `gcloud run deploy personal-os --source backend/`
3. Set env vars in Cloud Console
4. Update the `baseUrl` in api_service.dart

## For Now

Set up the cron-job.org ping above. It takes 2 minutes and solves the problem
immediately. Migrate to a better host when you're ready to share with others.
