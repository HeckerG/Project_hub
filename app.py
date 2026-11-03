import os
from decimal import Decimal
import pandas as pd
import streamlit as st
import mysql.connector
from mysql.connector import Error

st.set_page_config(page_title="ProjectHub | Business Manager", page_icon="⚡", layout="wide")

st.markdown("""
<style>
.block-container {padding-top: 1.6rem; padding-bottom: 2rem;}
[data-testid="stMetric"] {background: rgba(120,120,120,.07); border: 1px solid rgba(120,120,120,.16); padding: 14px; border-radius: 12px;}
div[data-testid="stSidebar"] {border-right: 1px solid rgba(120,120,120,.15);}
.small-muted {color: #888; font-size: .88rem;}
</style>
""", unsafe_allow_html=True)

st.title("⚡ ProjectHub")
st.caption("Electronics Project Business & Inventory Management")

def get_config():
    """Load database settings from Streamlit Secrets or environment variables."""
    if "mysql" in st.secrets:
        config = dict(st.secrets["mysql"])
    else:
        config = {
            "host": os.getenv("DB_HOST", "127.0.0.1"),
            "port": int(os.getenv("DB_PORT", "3306")),
            "user": os.getenv("DB_USER", "root"),
            "password": os.getenv("DB_PASSWORD", ""),
            "database": os.getenv("DB_NAME", "projecthub"),
        }
        env_ca = os.getenv("DB_SSL_CA")
        if env_ca:
            config["ssl_ca_path"] = env_ca

    # Streamlit Secrets can store the PEM certificate as multiline text.
    ca_text = config.pop("ssl_ca", None)
    ca_path = config.pop("ssl_ca_path", None)

    if ca_text:
        ca_path = _write_ca_certificate(ca_text)

    host = config.get("host", "")
    if "aivencloud.com" in host and not ca_path:
        raise RuntimeError(
            "Aiven requires its CA certificate. Add the full CA certificate "
            "contents as ssl_ca in Streamlit Secrets."
        )

    if ca_path:
        config.update({
            "ssl_ca": ca_path,
            "ssl_verify_cert": True,
            "ssl_verify_identity": True,
        })

    config["port"] = int(config.get("port", 3306))
    return config


@st.cache_resource
def _write_ca_certificate(certificate_text):
    """Write the public CA certificate from Streamlit Secrets to a temp PEM file."""
    import tempfile

    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".pem", prefix="projecthub-aiven-ca-", delete=False
    ) as cert_file:
        cert_file.write(certificate_text.strip() + "\\n")
        return cert_file.name


@st.cache_resource
def get_connection():
    config = get_config()
    return mysql.connector.connect(
        **config,
        autocommit=False,
        connection_timeout=20,
    )

def run_query(sql, params=None, fetch=True):
    conn = get_connection()
    cur = conn.cursor(dictionary=True)
    try:
        cur.execute(sql, params or ())
        rows = cur.fetchall() if fetch else None
        conn.commit()
        return rows
    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close()

def run_write(sql, params=None):
    return run_query(sql, params, fetch=False)

def money(value):
    return f"₹{float(value or 0):,.2f}"

def show_error(err):
    st.error(f"Database operation failed: {err}")
    st.caption("Check that MySQL is running and the ProjectHub setup SQL has been executed.")

try:
    conn = get_connection()
    if not conn.is_connected():
        st.error("Could not connect to MySQL.")
        st.stop()
except Exception as exc:
    st.error("ProjectHub cannot connect to MySQL.")
    st.code(str(exc))
    st.info("Check the [mysql] settings in Streamlit Secrets. For Aiven, use the cloud host, port 18076, database projecthub, and the full CA certificate in ssl_ca.")
    st.stop()

pages = ["Dashboard", "Orders", "New Order", "Customers", "Projects", "Inventory", "Purchases", "Payments", "Expenses", "Reports"]
page = st.sidebar.radio("Navigation", pages)
st.sidebar.divider()
st.sidebar.caption("Connected to MySQL · projecthub")
st.sidebar.caption("Demo dataset contains fictional customer and supplier records.")

if page == "Dashboard":
    st.subheader("Business overview")
    c1, c2, c3, c4 = st.columns(4)
    try:
        totals = run_query("""
        SELECT
          (SELECT COUNT(*) FROM orders) AS orders_count,
          (SELECT COALESCE(SUM(amount),0) FROM payments) AS revenue_received,
          (SELECT COALESCE(SUM(pending_amount),0) FROM v_order_balances WHERE status <> 'CANCELLED') AS pending,
          (SELECT COUNT(*) FROM v_low_stock) AS low_stock
        """)[0]
        c1.metric("Total orders", totals["orders_count"])
        c2.metric("Payments received", money(totals["revenue_received"]))
        c3.metric("Pending payments", money(totals["pending"]))
        c4.metric("Low-stock parts", totals["low_stock"])
        st.markdown("### Order status")
        status = pd.DataFrame(run_query("SELECT status, COUNT(*) AS orders FROM orders GROUP BY status ORDER BY orders DESC"))
        if not status.empty:
            st.bar_chart(status.set_index("status"))
        left, right = st.columns(2)
        with left:
            st.markdown("### Recent orders")
            recent = pd.DataFrame(run_query("""
                SELECT order_id, customer_name, status, order_total, amount_paid, pending_amount
                FROM v_order_balances ORDER BY order_id DESC LIMIT 7
            """))
            st.dataframe(recent, use_container_width=True, hide_index=True)
        with right:
            st.markdown("### Components requiring restock")
            low = pd.DataFrame(run_query("SELECT part_name, quantity_in_stock, minimum_stock FROM v_low_stock ORDER BY part_name"))
            if low.empty:
                st.success("No low-stock components.")
            else:
                st.dataframe(low, use_container_width=True, hide_index=True)
        st.markdown("### Top-selling projects")
        top = pd.DataFrame(run_query("""
            SELECT p.project_name, SUM(oi.quantity) AS units_sold,
                   SUM(oi.quantity * oi.unit_price) AS sales_value
            FROM projects p JOIN order_items oi ON oi.project_id=p.project_id
            JOIN orders o ON o.order_id=oi.order_id
            WHERE o.status <> 'CANCELLED'
            GROUP BY p.project_id,p.project_name
            ORDER BY units_sold DESC, sales_value DESC LIMIT 8
        """))
        if not top.empty:
            st.dataframe(top, use_container_width=True, hide_index=True)
    except Exception as e:
        show_error(e)

elif page == "Orders":
    st.subheader("Order management")
    try:
        df = pd.DataFrame(run_query("""
            SELECT order_id, customer_name, status, order_total, amount_paid, pending_amount
            FROM v_order_balances ORDER BY order_id DESC
        """))
        st.dataframe(df, use_container_width=True, hide_index=True)
        st.markdown("### Update order status")
        orders = run_query("SELECT order_id,status FROM orders ORDER BY order_id DESC")
        if orders:
            labels = {f"#{o['order_id']} · {o['status']}": o["order_id"] for o in orders}
            with st.form("status_form"):
                selected = st.selectbox("Order", list(labels))
                new_status = st.selectbox("New status", ["PENDING","IN_PROGRESS","READY","DELIVERED","CANCELLED"])
                submitted = st.form_submit_button("Update status")
            if submitted:
                run_write("UPDATE orders SET status=%s WHERE order_id=%s", (new_status, labels[selected]))
                st.success("Order status updated.")
                st.rerun()
    except Exception as e:
        show_error(e)

elif page == "New Order":
    st.subheader("Create a customer order")
    customers = run_query("SELECT customer_id,full_name FROM customers ORDER BY full_name")
    projects = run_query("SELECT project_id,project_name,default_selling_price FROM projects WHERE active=1 ORDER BY project_name")
    if not customers or not projects:
        st.warning("Add at least one customer and one active project first.")
    else:
        with st.form("new_order_form"):
            customer_map = {f"{c['full_name']} (#{c['customer_id']})": c["customer_id"] for c in customers}
            project_map = {p["project_name"]: p for p in projects}
            customer_label = st.selectbox("Customer", list(customer_map))
            project_label = st.selectbox("Project", list(project_map))
            qty = st.number_input("Quantity", min_value=1, max_value=100, value=1)
            default_price = float(project_map[project_label]["default_selling_price"])
            price = st.number_input("Selling price per unit (₹)", min_value=0.0, value=default_price, step=50.0)
            order_date = st.date_input("Order date")
            due_date = st.date_input("Expected delivery date")
            notes = st.text_area("Notes")
            submit = st.form_submit_button("Create order", type="primary")
        if submit:
            if due_date < order_date:
                st.error("Delivery date cannot be earlier than order date.")
            else:
                try:
                    db = get_connection()
                    cur = db.cursor()
                    cur.execute("INSERT INTO orders(customer_id,order_date,due_date,status,notes) VALUES(%s,%s,%s,'PENDING',%s)",
                                (customer_map[customer_label], order_date, due_date, notes))
                    oid = cur.lastrowid
                    cur.execute("INSERT INTO order_items(order_id,project_id,quantity,unit_price) VALUES(%s,%s,%s,%s)",
                                (oid, project_map[project_label]["project_id"], qty, Decimal(str(price))))
                    db.commit()
                    st.success(f"Order #{oid} created successfully.")
                except Exception as e:
                    get_connection().rollback()
                    show_error(e)
                finally:
                    try: cur.close()
                    except: pass

elif page == "Customers":
    st.subheader("Customer directory")
    with st.expander("Add customer"):
        with st.form("customer_form"):
            name = st.text_input("Full name")
            phone = st.text_input("Phone")
            email = st.text_input("Email")
            notes = st.text_area("Notes")
            submit = st.form_submit_button("Add customer")
        if submit:
            if not name.strip():
                st.warning("Customer name is required.")
            else:
                try:
                    run_write("INSERT INTO customers(full_name,phone,email,notes) VALUES(%s,%s,%s,%s)",
                              (name.strip(), phone or None, email or None, notes or None))
                    st.success("Customer added.")
                    st.rerun()
                except Exception as e: show_error(e)
    try:
        df = pd.DataFrame(run_query("""
            SELECT c.customer_id,c.full_name,c.phone,c.email,COUNT(DISTINCT o.order_id) AS total_orders,
                   COALESCE(SUM(v.pending_amount),0) AS pending_amount
            FROM customers c LEFT JOIN orders o ON o.customer_id=c.customer_id
            LEFT JOIN v_order_balances v ON v.order_id=o.order_id
            GROUP BY c.customer_id,c.full_name,c.phone,c.email ORDER BY c.full_name
        """))
        st.dataframe(df, use_container_width=True, hide_index=True)
    except Exception as e: show_error(e)

elif page == "Projects":
    st.subheader("Project catalogue")
    with st.expander("Add project"):
        with st.form("project_form"):
            name = st.text_input("Project name")
            desc = st.text_area("Description")
            price = st.number_input("Default selling price (₹)", min_value=0.0, step=50.0)
            submit = st.form_submit_button("Add project")
        if submit:
            if not name.strip(): st.warning("Project name is required.")
            else:
                try:
                    run_write("INSERT INTO projects(project_name,description,default_selling_price) VALUES(%s,%s,%s)",
                              (name.strip(), desc, Decimal(str(price))))
                    st.success("Project added.")
                    st.rerun()
                except Exception as e: show_error(e)
    try:
        df = pd.DataFrame(run_query("""
            SELECT p.project_id,p.project_name,p.description,p.default_selling_price,p.active,
                   COUNT(DISTINCT oi.order_item_id) AS order_lines
            FROM projects p LEFT JOIN order_items oi ON oi.project_id=p.project_id
            GROUP BY p.project_id,p.project_name,p.description,p.default_selling_price,p.active
            ORDER BY p.project_name
        """))
        st.dataframe(df, use_container_width=True, hide_index=True)
    except Exception as e: show_error(e)

elif page == "Inventory":
    st.subheader("Inventory control")
    a,b,c = st.columns(3)
    try:
        inventory = run_query("SELECT COUNT(*) AS parts_count, COALESCE(SUM(quantity_in_stock*standard_unit_cost),0) AS stock_value FROM parts")[0]
        a.metric("Component types", inventory["parts_count"])
        b.metric("Inventory value (standard cost)", money(inventory["stock_value"]))
        c.metric("Low-stock items", len(run_query("SELECT part_id FROM v_low_stock")))
        with st.expander("Add a new component"):
            with st.form("part_form"):
                pname = st.text_input("Component name")
                category = st.text_input("Category")
                unit = st.selectbox("Unit", ["pcs","set","meter","pack"])
                min_stock = st.number_input("Minimum stock", min_value=0, value=2)
                unit_cost = st.number_input("Standard unit cost (₹)", min_value=0.0, step=1.0)
                submit = st.form_submit_button("Add component")
            if submit:
                if not pname.strip(): st.warning("Component name is required.")
                else:
                    try:
                        run_write("""INSERT INTO parts(part_name,category,unit,minimum_stock,standard_unit_cost)
                                     VALUES(%s,%s,%s,%s,%s)""",
                                  (pname.strip(),category,unit,min_stock,Decimal(str(unit_cost))))
                        st.success("Component added. Add opening quantity using a stock adjustment below.")
                        st.rerun()
                    except Exception as e: show_error(e)
        df = pd.DataFrame(run_query("""
            SELECT part_id,part_name,category,quantity_in_stock,minimum_stock,standard_unit_cost,
                   quantity_in_stock*standard_unit_cost AS stock_value
            FROM parts ORDER BY part_name
        """))
        st.dataframe(df, use_container_width=True, hide_index=True)
        st.markdown("### Record stock adjustment")
        parts = run_query("SELECT part_id,part_name,quantity_in_stock FROM parts ORDER BY part_name")
        partmap = {f"{p['part_name']} · current: {p['quantity_in_stock']}":p for p in parts}
        with st.form("adjust_form"):
            chosen = st.selectbox("Component", list(partmap))
            direction = st.radio("Adjustment", ["Add stock","Remove stock"], horizontal=True)
            amount = st.number_input("Quantity", min_value=1, value=1)
            reason = st.text_input("Reason", value="Manual inventory adjustment")
            submit = st.form_submit_button("Record movement")
        if submit:
            p = partmap[chosen]
            delta = int(amount) if direction == "Add stock" else -int(amount)
            typ = "ADJUSTMENT_IN" if delta > 0 else "ADJUSTMENT_OUT"
            try:
                run_write("INSERT INTO stock_movements(part_id,movement_type,quantity_change,notes) VALUES(%s,%s,%s,%s)",
                          (p["part_id"],typ,delta,reason))
                st.success("Stock movement recorded and balance updated.")
                st.rerun()
            except Exception as e: show_error(e)
        with st.expander("Recent stock movement history"):
            hist = pd.DataFrame(run_query("""
                SELECT sm.movement_id,p.part_name,sm.movement_type,sm.quantity_change,sm.notes,sm.moved_at
                FROM stock_movements sm JOIN parts p ON p.part_id=sm.part_id
                ORDER BY sm.moved_at DESC LIMIT 100
            """))
            st.dataframe(hist, use_container_width=True, hide_index=True)
    except Exception as e: show_error(e)

elif page == "Purchases":
    st.subheader("Supplier purchases")
    suppliers = run_query("SELECT supplier_id,supplier_name FROM suppliers ORDER BY supplier_name")
    parts = run_query("SELECT part_id,part_name FROM parts ORDER BY part_name")
    with st.expander("Create purchase order"):
        if not suppliers or not parts:
            st.info("Add suppliers and components in the database first.")
        else:
            with st.form("purchase_form"):
                smap = {s["supplier_name"]:s["supplier_id"] for s in suppliers}
                pmap = {p["part_name"]:p["part_id"] for p in parts}
                supplier = st.selectbox("Supplier",list(smap))
                part = st.selectbox("Component",list(pmap))
                qty = st.number_input("Quantity",min_value=1,value=5)
                cost = st.number_input("Unit purchase cost (₹)",min_value=0.0,step=1.0)
                date = st.date_input("Purchase date")
                submit = st.form_submit_button("Create purchase")
            if submit:
                try:
                    db=get_connection(); cur=db.cursor()
                    cur.execute("INSERT INTO purchases(supplier_id,purchase_date,status) VALUES(%s,%s,'ORDERED')",(smap[supplier],date))
                    pid=cur.lastrowid
                    cur.execute("INSERT INTO purchase_items(purchase_id,part_id,quantity,unit_cost) VALUES(%s,%s,%s,%s)",
                                (pid,pmap[part],qty,Decimal(str(cost))))
                    db.commit(); st.success(f"Purchase #{pid} created. Receive it below to add stock.")
                    st.rerun()
                except Exception as e:
                    get_connection().rollback(); show_error(e)
                finally:
                    try: cur.close()
                    except: pass
    try:
        purchases = pd.DataFrame(run_query("""
            SELECT pu.purchase_id,s.supplier_name,pu.purchase_date,pu.status,
                   COALESCE(SUM(pi.quantity*pi.unit_cost),0) AS purchase_total
            FROM purchases pu JOIN suppliers s ON s.supplier_id=pu.supplier_id
            LEFT JOIN purchase_items pi ON pi.purchase_id=pu.purchase_id
            GROUP BY pu.purchase_id,s.supplier_name,pu.purchase_date,pu.status
            ORDER BY pu.purchase_id DESC
        """))
        st.dataframe(purchases,use_container_width=True,hide_index=True)
        pending = run_query("SELECT purchase_id FROM purchases WHERE status='ORDERED' ORDER BY purchase_id")
        if pending:
            selected = st.selectbox("Purchase to receive", [p["purchase_id"] for p in pending])
            if st.button("Mark selected purchase as received",type="primary"):
                try:
                    run_write("CALL receive_purchase(%s)",(selected,))
                    st.success("Purchase received. Inventory has been updated.")
                    st.rerun()
                except Exception as e: show_error(e)
    except Exception as e: show_error(e)

elif page == "Payments":
    st.subheader("Payment tracking")
    try:
        balances = run_query("""
            SELECT order_id,customer_name,order_total,amount_paid,pending_amount,status
            FROM v_order_balances WHERE status <> 'CANCELLED' ORDER BY order_id DESC
        """)
        st.dataframe(pd.DataFrame(balances),use_container_width=True,hide_index=True)
        options = {f"Order #{r['order_id']} · {r['customer_name']} · pending {money(r['pending_amount'])}":r for r in balances if Decimal(str(r["pending_amount"])) > 0}
        st.markdown("### Record a payment")
        if options:
            with st.form("payment_form"):
                selected = st.selectbox("Order",list(options))
                amount = st.number_input("Amount received (₹)",min_value=1.0,step=50.0)
                method = st.selectbox("Payment method",["UPI","CASH","BANK_TRANSFER","OTHER"])
                ref = st.text_input("Reference number (optional)")
                submit = st.form_submit_button("Save payment")
            if submit:
                row=options[selected]
                if Decimal(str(amount)) > Decimal(str(row["pending_amount"])):
                    st.error("Payment cannot exceed the outstanding balance.")
                else:
                    try:
                        run_write("INSERT INTO payments(order_id,amount,method,reference_no) VALUES(%s,%s,%s,%s)",
                                  (row["order_id"],Decimal(str(amount)),method,ref or None))
                        st.success("Payment recorded.")
                        st.rerun()
                    except Exception as e: show_error(e)
        else:
            st.success("No outstanding payments.")
    except Exception as e: show_error(e)

elif page == "Expenses":
    st.subheader("Business expenses")
    with st.form("expense_form"):
        col1,col2=st.columns(2)
        with col1:
            category=st.selectbox("Category",["Packaging","Transport","Tools","Marketing","Miscellaneous","Other"])
            amount=st.number_input("Amount (₹)",min_value=1.0,step=10.0)
        with col2:
            date=st.date_input("Expense date")
            orders=run_query("SELECT order_id FROM orders ORDER BY order_id DESC")
            order_ids=[None]+[o["order_id"] for o in orders]
            order=st.selectbox("Related order (optional)",order_ids,format_func=lambda x:"General expense" if x is None else f"Order #{x}")
        description=st.text_input("Description")
        submit=st.form_submit_button("Add expense")
    if submit:
        try:
            run_write("INSERT INTO expenses(order_id,expense_date,category,description,amount) VALUES(%s,%s,%s,%s,%s)",
                      (order,date,category,description,Decimal(str(amount))))
            st.success("Expense saved.")
            st.rerun()
        except Exception as e: show_error(e)
    try:
        df=pd.DataFrame(run_query("SELECT expense_id,expense_date,category,description,amount,order_id FROM expenses ORDER BY expense_date DESC"))
        st.dataframe(df,use_container_width=True,hide_index=True)
    except Exception as e: show_error(e)

elif page == "Reports":
    st.subheader("Business reports")
    try:
        col1,col2=st.columns(2)
        with col1:
            st.markdown("### Sales by project")
            sales=pd.DataFrame(run_query("""
                SELECT p.project_name,SUM(oi.quantity) AS units,
                       SUM(oi.quantity*oi.unit_price) AS sales
                FROM projects p JOIN order_items oi ON oi.project_id=p.project_id
                JOIN orders o ON o.order_id=oi.order_id
                WHERE o.status <> 'CANCELLED'
                GROUP BY p.project_id,p.project_name ORDER BY sales DESC
            """))
            if not sales.empty:
                st.bar_chart(sales.set_index("project_name")["sales"])
                st.dataframe(sales,use_container_width=True,hide_index=True)
        with col2:
            st.markdown("### Outstanding customer balances")
            pending=pd.DataFrame(run_query("""
                SELECT customer_name,SUM(pending_amount) AS pending
                FROM v_order_balances WHERE status <> 'CANCELLED'
                GROUP BY customer_name HAVING pending > 0 ORDER BY pending DESC
            """))
            st.dataframe(pending,use_container_width=True,hide_index=True)
        st.markdown("### Monthly payment collections")
        monthly=pd.DataFrame(run_query("""
            SELECT DATE_FORMAT(paid_at,'%Y-%m') AS month,SUM(amount) AS collections
            FROM payments GROUP BY DATE_FORMAT(paid_at,'%Y-%m') ORDER BY month
        """))
        if not monthly.empty:
            st.line_chart(monthly.set_index("month"))
        st.markdown("### Expense summary")
        expense=pd.DataFrame(run_query("""
            SELECT category,SUM(amount) AS total_expense FROM expenses
            GROUP BY category ORDER BY total_expense DESC
        """))
        st.dataframe(expense,use_container_width=True,hide_index=True)
        st.caption("Sales value is based on order line totals. Payment collections are cash received. They are different accounting measures.")
    except Exception as e: show_error(e)

st.sidebar.divider()
st.sidebar.caption("ProjectHub · DBMS Academic Project")

