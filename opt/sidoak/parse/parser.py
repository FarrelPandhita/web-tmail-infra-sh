import os
import re
import time
import psycopg2
from dotenv import load_dotenv
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from email import policy
from email.parser import BytesParser

load_dotenv("/opt/sidoak/parser/.env")

DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASS = os.getenv("DB_PASS")
DB_HOST = os.getenv("DB_HOST")
MAILDIR = os.getenv("MAILDIR")

OTP_REGEX = [
    r'\b\d{4,8}\b',
    r'\b[A-Z0-9]{4,8}\b'
]


def db():
    return psycopg2.connect(
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASS,
        host=DB_HOST
    )


def extract_otp(text):
    text = text.upper()

    keywords = [
        "OTP",
        "CODE",
        "VERIFY",
        "VERIFICATION",
        "SECURITY",
        "LOGIN",
        "PASSCODE"
    ]

    for keyword in keywords:
        if keyword in text:
            for pattern in OTP_REGEX:
                match = re.search(pattern, text)
                if match:
                    return match.group(0)

    for pattern in OTP_REGEX:
        match = re.search(pattern, text)
        if match:
            return match.group(0)

    return None


class MailHandler(FileSystemEventHandler):

    def on_created(self, event):

        if event.is_directory:
            return

        try:
            time.sleep(1)

            with open(event.src_path, "rb") as f:
                msg = BytesParser(policy=policy.default).parse(f)

            sender = str(msg.get("From", ""))
            recipient = str(msg.get("To", ""))
            subject = str(msg.get("Subject", ""))

            body = ""

            if msg.is_multipart():
                for part in msg.walk():
                    content_type = part.get_content_type()

                    if content_type == "text/plain":
                        body += part.get_content()
            else:
                body = msg.get_content()

            combined_text = f"{subject}\n{body}"

            otp = extract_otp(combined_text)

            conn = db()
            cur = conn.cursor()

            cur.execute("""
                SELECT id
                FROM generated_emails
                WHERE generated_email=%s
                LIMIT 1
            """, (recipient.strip(),))

            email_row = cur.fetchone()

            if not email_row:
                print(f"Unknown email: {recipient}")
                cur.close()
                conn.close()
                return

            generated_email_id = email_row[0]

            cur.execute("""
                INSERT INTO inbox_messages
                (
                    generated_email_id,
                    sender,
                    recipient,
                    subject,
                    raw_body,
                    otp_code
                )
                VALUES (%s,%s,%s,%s,%s,%s)
            """, (
                generated_email_id,
                sender,
                recipient,
                subject,
                body,
                otp
            ))

            cur.execute("""
                INSERT INTO otp_cache
                (
                    generated_email_id,
                    latest_otp,
                    source
                )
                VALUES (%s,%s,%s)
                ON CONFLICT (generated_email_id)
                DO UPDATE
                SET latest_otp=EXCLUDED.latest_otp,
                    source=EXCLUDED.source,
                    updated_at=NOW()
            """, (
                generated_email_id,
                otp,
                sender
            ))

            conn.commit()

            cur.close()
            conn.close()

            print(
                f"[OK] {recipient} | OTP={otp}"
            )

        except Exception as e:
            print(f"[ERROR] {e}")


if __name__ == "__main__":
    print("SIDOAK OTP Parser Running...")

    observer = Observer()
    observer.schedule(
        MailHandler(),
        MAILDIR,
        recursive=False
    )

    observer.start()

    try:
        while True:
            time.sleep(2)
    except KeyboardInterrupt:
        observer.stop()

    observer.join()
