PROJECTHUB - STREAMLIT APPLICATION

WHAT IS INCLUDED
- app.py: complete Streamlit frontend and Python database operations
- database/ProjectHub_Full_Setup.sql: creates the MySQL database, 12 tables,
  demo data, constraints, views, triggers and stored procedure
- requirements.txt: Python dependencies
- .streamlit/secrets.toml.example: MySQL connection template

SETUP (Mac / Windows)
1. Install and start MySQL Server.
2. Open database/ProjectHub_Full_Setup.sql in MySQL Workbench.
3. Execute the complete script. It drops and recreates the projecthub database.
   Do not run it if you need to preserve an existing projecthub database.
4. Install Python 3.10 or newer.
5. Open Terminal in this ProjectHub_App folder and run:
      python3 -m venv .venv
      source .venv/bin/activate
   On Windows use:
      .venv\Scripts\activate
6. Install dependencies:
      pip install -r requirements.txt
7. Copy .streamlit/secrets.toml.example to .streamlit/secrets.toml
   and enter your MySQL username and password.
8. Start the application:
      streamlit run app.py

ALTERNATIVE CONNECTION
Set DB_HOST, DB_PORT, DB_USER, DB_PASSWORD and DB_NAME environment variables.
The application uses environment variables if Streamlit secrets are absent.

FEATURES
Dashboard, orders, new order creation, customers, project catalogue,
inventory, stock movement history, purchase receiving, payments, expenses,
and reports.

DEMO DATA
Customer and supplier identities and transaction records are fictional.
The demo data is intended for academic demonstration, not as real business
or accounting records.

IMPORTANT NOTES
- MySQL 8.0+ is required.
- The SQL setup file recreates the projecthub database.
- The app uses parameterized SQL statements.
- Inventory changes are recorded in stock_movements; the database trigger
  updates the parts quantity balance and blocks negative stock.
- The payment screen checks outstanding balance before recording a payment.
- For a classroom demo, run the SQL setup first, then start Streamlit.

TROUBLESHOOTING
- Access denied: check username/password in secrets.toml.
- Can't connect: confirm MySQL Server is running and port 3306 is available.
- Unknown database: execute the full SQL setup.
- Missing module: activate the virtual environment and run pip install -r requirements.txt.
