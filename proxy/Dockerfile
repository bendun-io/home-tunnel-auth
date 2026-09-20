FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && rm -f /etc/nginx/conf.d/default.conf

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
