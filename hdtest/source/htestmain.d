module htestmain;

import std.stdio;
import std.string;
import std.conv;
import hibernated.core;
import std.traits;
version( USE_SQLITE )
{
    import ddbc.drivers.sqliteddbc;
    import hibernated.dialects.sqlitedialect;
}
version( USE_PGSQL )
{
    import ddbc.drivers.pgsqlddbc;
    import hibernated.dialects.pgsqldialect;
}

// Annotations of entity classes
@Table( "gebruiker" )
class User {
    long id;
    @UniqueKey
    string name;
    int some_field_with_underscore;
    @ManyToMany // cannot be inferred, requires annotation
    LazyCollection!Role roles;
    //@ManyToOne
    MyGroup group;
    bool active;

    override string toString() { return "user: " ~ to!string( id ) ~ " " ~ name; }
}

class Role {
    int id;
    string name;
    @ManyToMany // w/o this annotation will be OneToMany by convention
        LazyCollection!User users;
}

@Entity
class MyGroup {
    long id;
    string name;
    @OneToMany
    LazyCollection!User users;
}

@Entity
class Token {
    long id;
    @NotNull
    @UniqueKey
    string   name;
    @UniqueKey
    string   token;
}


//private to the module
private DataSource ds = null;
private Dialect dialect = null;


void initDataSource() {
    // setup DB connection
    version( USE_SQLITE )
    {
        SQLITEDriver driver = new SQLITEDriver();
        string[string] params;
        ds = new ConnectionPoolDataSourceImpl(driver, "zzz.db", params);
        dialect = new SQLiteDialect();
    }
    version( USE_PGSQL )
    {
        string url = PGSQLDriver.generateUrl( "/tmp", 5432, "testdb" );
        string[string] params;
        params["user"] = "hdtest";
        params["password"] = "secret";
        params["ssl"] = "true";
        PGSQLDriver driver = new PGSQLDriver();
        ds = new ConnectionPoolDataSourceImpl(driver, url, params);
        dialect = new PGSQLDialect();
    }
}

void testHibernate() {
    // create metadata from annotations
    writeln("Creating schema from class list");
    EntityMetaData schema = new SchemaInfoImpl!(User, Role, MyGroup, Token);
    //writeln("Creating schema from module list");
    //EntityMetaData schema2 = new SchemaInfoImpl!(htestmain);


    writeln("Creating session factory");
    // create session factory
    initDataSource();
    assert( ds );
    SessionFactory factory = new SessionFactoryImpl(schema, dialect, ds);
    scope(exit) factory.close();

    writeln("Creating DB schema");
    DBInfo db = factory.getDBMetaData();
    {
        Connection conn = ds.getConnection();
        scope(exit) conn.close();
        db.updateDBSchema(conn, true, true);
    }


    // create session
    Session sess = factory.openSession();
    scope(exit) sess.close();

    // use session to access DB

    writeln("Querying empty DB");
    Query q = sess.createQuery("FROM User ORDER BY name");
    User[] list = q.list!User();
    writeln("Result size is " ~ to!string(list.length));

    // create sample data
    writeln("Creating sample schema");
    MyGroup grp1 = new MyGroup();
    grp1.name = "Group-1";
    MyGroup grp2 = new MyGroup();
    grp2.name = "Group-2";
    MyGroup grp3 = new MyGroup();
    grp3.name = "Group-3";
    //
    Role r10 = new Role();
    r10.name = "role10";
    Role r11 = new Role();
    r11.name = "role11";
    //
    User u10 = new User();
    u10.name = "Alex";
    u10.roles = [r10, r11];
    u10.group = grp3;
    u10.active = true;
    User u12 = new User();
    u12.name = "Arjan";
    u12.roles = [r10, r11];
    u12.group = grp2;
    u12.active = true;
    User u13 = new User();
    u13.name = "Wessel";
    u13.roles = [r10, r11];
    u13.group = grp2;
    u13.active = false;

    writeln("saving group 1-2-3" );
    sess.save( grp1 );
    sess.save( grp2 );
    sess.save( grp3 );
    writeln("Saving r10");
    sess.save(r10);
    writeln("Saving r11");
    sess.save(r11);
    writeln("Saving u10");
    sess.save(u10);
    writeln("Saving u12");
    sess.save(u12);
    writeln("Saving u13");
    sess.save(u13);

    writeln("Loading User");
    // load and check data
    auto qresult = sess.createQuery("FROM User WHERE name=:Name and some_field_with_underscore != 42").setParameter("Name", "Alex");
    writefln( "query result: %s", qresult.listRows() );
    User u11 = qresult.uniqueResult!User();
    //User u11 = sess.createQuery("FROM User WHERE name=:Name and some_field_with_underscore != 42").setParameter("Name", "Alex").uniqueResult!User();
    writeln("Checking User");
    assert(u11.roles.length == 2);
    assert(u11.roles[0].name == "role10" || u11.roles.get()[0].name == "role11");
    assert(u11.roles[1].name == "role10" || u11.roles.get()[1].name == "role11");
    assert(u11.roles[0].users.length == 3);
    assert(u11.roles[0].users[0] == u10);

    //writeln("Removing User");
    // remove reference
    //std.algorithm.remove(u11.roles.get(), 0);
    //sess.update(u11);

    // remove entity
    //sess.remove(u11);
}

void testReadBack() {
    writeln( "test read back with new db session" );
    if( ds is null ) initDataSource();
    assert( ds );
    EntityMetaData schema = new SchemaInfoImpl!(User, Role, MyGroup, Token);
    SessionFactory factory = new SessionFactoryImpl( schema, dialect, ds );
    scope(exit) factory.close();

    writeln("Creating DB schema");

    // create session
    Session sess = factory.openSession();
    scope(exit) sess.close();

    // use session to access DB
    writeln("Querying DB Users");
    Query q = sess.createQuery("FROM User ORDER BY name");
    User[] list = q.list!User();
    writeln("Result size is " ~ to!string(list.length));
    foreach( ref u; list[0].roles[0].users )
        writeln( u );

    writeln("Query DB group" );
    auto qresult = sess.createQuery("FROM MyGroup WHERE id=:id").setParameter( "id", 2 );
    MyGroup grp2 = qresult.uniqueResult!MyGroup();
    foreach( ref u; grp2.users )
        writeln( u );
}


void main()
{
    try {
        testHibernate();
        testReadBack();
    } catch( Exception e )
    {
        writeln( e );
    }
    writeln("Press any key");
    readln();

}
