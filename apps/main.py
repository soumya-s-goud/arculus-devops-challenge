from flask import Flask, jsonify, request
from flask_sqlalchemy import SQLAlchemy
from dotenv import load_dotenv
import os

# Load environment variables
dotenv_path = os.path.join(os.path.dirname(__file__), "passwords.env")
load_dotenv(dotenv_path=dotenv_path)

app = Flask(__name__)

# Define database configuration
app.config["SQLALCHEMY_DATABASE_URI"] = (
    f"postgresql://{os.getenv('DB_USER')}:"
    f"{os.getenv('DB_PASSWORD')}@{os.getenv('DB_HOST')}:"
    f"{os.getenv('DB_PORT')}/{os.getenv('DB_NAME')}"
)
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

db = SQLAlchemy(app)


# Define the Order model
class Order(db.Model):
    __tablename__ = "orders"
    id = db.Column(db.String, primary_key=True)
    amount = db.Column(db.Float, nullable=False)


# Routes
@app.route("/health", methods=["GET"])
def check_health():
    return jsonify({"status": "ok"}), 200


@app.route("/orders", methods=["GET", "POST"])
def orders():
    if request.method == "GET":
        all_orders = db.session.query(Order).all()
        return jsonify(
            [{"id": order.id, "amount": order.amount} for order in all_orders]
        )
    elif request.method == "POST":
        data = request.get_json()

        # Validate payload
        if not data or "id" not in data or "amount" not in data:
            return (
                jsonify(
                    {"error": "Invalid input. 'id' and 'amount' are required fields."}
                ),
                400,
            )

        # Create the new order
        new_order = Order(id=data["id"], amount=data["amount"])
        db.session.add(new_order)
        db.session.commit()
        return jsonify({"id": new_order.id, "amount": new_order.amount}), 201


def start_application():
    """
    Initialize the database and start the Flask app server if called directly.
    """
    with app.app_context():
        db.create_all()
    app.run(host="0.0.0.0", port=5000)


if __name__ == "__main__":
    start_application()
