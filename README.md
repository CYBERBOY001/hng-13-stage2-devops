

# 🟢 Blue/Green Deployment with Nginx Auto-Failover

This repository implements a **Blue/Green deployment strategy** for **Node.js services** using **Docker Compose** and **Nginx**.  
The setup routes traffic to a **primary (active)** pool (**Blue** or **Green**) by default, with **automatic failover** to the backup pool on detection of **errors, timeouts, or 5xx responses**.

Failover happens **within the same client request** via **Nginx retries**, ensuring **zero failed requests** to clients.  
Custom headers (`X-App-Pool` and `X-Release-Id`) are forwarded unchanged.

---

## 🧰 Prerequisites

- **Docker** and **Docker Compose** installed
- Access to the **pre-built container images** for Blue and Green (provided via `BLUE_IMAGE` and `GREEN_IMAGE` env vars)

---

## ⚙️ Setup

1. **Clone the repository**
   ```bash
   git clone <https://github.com/CYBERBOY001/hng-13-stage2-devops.git>
   cd hng-13-stage2-devops


2. **Copy the example environment file**

   ```bash
   cp .env.example .env
   ```

3. **Edit `.env` to set:**

   * `BLUE_IMAGE` and `GREEN_IMAGE`: Full image references (e.g., `your-registry/nodejs-app:blue-v1`)
   * `ACTIVE_POOL`: `blue` (default, primary) or `green`
   * `RELEASE_ID_BLUE` and `RELEASE_ID_GREEN`: Strings passed to apps for `X-Release-Id` header
   * `PORT`: Optional, defaults to **8080** for Nginx

4. **Start the services**

   ```bash
   docker compose up -d
   ```

   This generates the **Nginx config dynamically** based on `ACTIVE_POOL`, starts:

   * Blue app on port **8081**
   * Green app on port **8082**
   * Nginx on the specified port

---

## 🧪 Testing

### ✅ Baseline (Blue Active)

All traffic routes to **Blue**:
 * NOTE: if you're running your stack on VM replace localhost with your VM public IP

```bash
curl -v http://localhost:8080/version
```

**Expected:**

```
200 OK
X-App-Pool: blue
X-Release-Id: v1.0.0-blue
```

---

### ⚠️ Induce Failover (Chaos on Blue)

Simulate downtime on Blue (direct access):

```bash
curl -X POST "http://localhost:8081/chaos/start?mode=error"
```

Or for timeout:

```bash
curl -X POST "http://localhost:8081/chaos/start?mode=timeout"
```

**Verify failover:**

```bash
curl -v http://localhost:8080/version
```

**Expected:**

```
200 OK
X-App-Pool: green
X-Release-Id: "v1.0.0-green
```

During chaos, loop requests to `/version` (e.g., via script):
**≥95% should succeed from Green** with **no non-200s**.

**Restore:**

```bash
curl -X POST "http://localhost:8081/chaos/stop"
```

---


## ❤️ Health Checks

* Apps expose `/healthz` for **liveness** (used in Compose `healthcheck`)
* Nginx uses **passive health** via request failures
  (`max_fails=1`, `fail_timeout=1s`)

---

## 🧾 Logs and Debugging

* View all logs:

  ```bash
  docker compose logs -f
  ```
* View Nginx logs:

  ```bash
  docker compose exec nginx cat /var/log/nginx/error.log
  ```
* Test direct app access:

  ```bash
  curl http://localhost:8081/healthz   # Blue
  curl http://localhost:8082/healthz   # Green
  ```

---

## 🤖 CI / Grader Integration

Set environment variables (e.g., via CI secrets) and run:

```bash
docker compose up -d
```

The grader can:

* Trigger chaos on **8081/8082**
* Verify responses on **8080**
* No image builds required (uses pre-built images)

---

## ⚠️ Constraints & Compliance

* ❌ No Kubernetes / Swarm / Service meshes — **pure Docker Compose**
* ❌ No app modifications — headers forwarded via `proxy_pass_header`
* ⏱ Request timeouts **<10s total** (`connect=1s`, `read/send=3s`)
* 🔁 Failover retries occur **within a single request**
* 🧩 Backup pool used **only when primary fails**

---
