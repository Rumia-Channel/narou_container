FROM nginx:stable

COPY conf.d /etc/nginx/conf.d
COPY ssl /etc/nginx/ssl
COPY wait.sh /wait.sh

RUN chmod +x /wait.sh

CMD ["/wait.sh"]
