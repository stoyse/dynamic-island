# Static landing page for Dynamic Island — served by nginx.
# The app source (Swift) is irrelevant here; we only ship the website/ folder.
FROM nginx:1.27-alpine

# nginx config (gzip + long-cache assets, no-cache html)
COPY website/nginx.conf /etc/nginx/conf.d/default.conf

# the actual site
COPY website/ /usr/share/nginx/html/
# nginx.conf doesn't belong in the served root
RUN rm -f /usr/share/nginx/html/nginx.conf

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost/ >/dev/null 2>&1 || exit 1
