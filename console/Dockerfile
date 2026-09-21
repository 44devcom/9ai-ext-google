FROM google/cloud-sdk:slim

COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && mkdir -p /secrets \
    && chmod 700 /secrets

ENV GOOGLE_APPLICATION_CREDENTIALS=/secrets/gcp-key.json

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
