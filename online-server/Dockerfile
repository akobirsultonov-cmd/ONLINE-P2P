FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY main.py ./
COPY static ./static
RUN useradd -m p2p && mkdir /data && chown p2p:p2p /data
USER p2p
ENV P2P_DB_PATH=/data/p2p.sqlite3
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
