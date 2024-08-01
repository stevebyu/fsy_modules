component threadSafe extends="o3.internal.cfc.model" {
	property name="injector" inject="wirebox";

	variables.dsn = { prod = "fsyweb_pro", dev = "fsyweb_dev", local = "fsyweb_local" }
	variables.dsn.scheduler = variables.dsn.local
	variables.dsn.prereg = variables.dsn.prod
	variables.realProgram = 80000082
  variables.selector_f = 10000180
  variables.selector_m = 10000181
  variables.pm_selector_set_template = 10000024
	variables.trainingProgram = structKeyExists(application, "trainingProgram") ? application.trainingProgram : 80001055
	variables.ticket = "FSY-2980"
	variables.ticketName = reReplace(variables.ticket, "-", "_", "all")

  // /////
  // SETUP
  // /////

  // create products
  public struct function create_product_section() {
    queryExecute("
      insert into product (MASTER_TYPE, PROGRAM, STATUS, SHORT_TITLE, TITLE, DEPARTMENT, PRODUCT_TYPE, INCLUDE_IN_ENROLLMENT_TOTAL, CREATED_BY)
      values ('Section', #variables.realProgram#, 'Active', '#variables.ticketName#_SECTION', '#variables.ticketName# Test Section', 'FSY', 'FSY', 'Y', '#variables.ticketName#')
    ", {}, { datasource: variables.dsn.local, result: "local.section" });
    if (!local.section.keyExists("generatedKey")) throw(type = "ds.error", message = "Failed to create section product", detail = serializeJSON(local.section))

    queryExecute("
      insert into product (MASTER_TYPE, PROGRAM, STATUS, SHORT_TITLE, TITLE, DEPARTMENT, PRODUCT_TYPE, INCLUDE_IN_ENROLLMENT_TOTAL, CREATED_BY, OPTION_TYPE, HOUSING_TYPE)
      values ('Option', #variables.realProgram#, 'Active', '#variables.ticketName#_OPTION_M', '#variables.ticketName# Test Option', 'FSY', 'FSY', 'Y', '#variables.ticketName#', 'Housing', 'Male')
    ", {}, { datasource: variables.dsn.local, result: "local.option_m" });
    if (!local.option_m.keyExists("generatedKey")) throw(type = "ds.error", message = "Failed to create option product", detail = serializeJSON(local.option_m))
    queryExecute("
      insert into product (MASTER_TYPE, PROGRAM, STATUS, SHORT_TITLE, TITLE, DEPARTMENT, PRODUCT_TYPE, INCLUDE_IN_ENROLLMENT_TOTAL, CREATED_BY, OPTION_TYPE, HOUSING_TYPE)
      values ('Option', #variables.realProgram#, 'Active', '#variables.ticketName#_OPTION_F', '#variables.ticketName# Test Option', 'FSY', 'FSY', 'Y', '#variables.ticketName#', 'Housing', 'Female')
    ", {}, { datasource: variables.dsn.local, result: "local.option_f" });
    if (!local.option_f.keyExists("generatedKey")) throw(type = "ds.error", message = "Failed to create option product", detail = serializeJSON(local.option_f))

    queryExecute("
      insert into option_group (SECTION, NAME, MIN_CHOICE, MAX_CHOICE, CREATED_BY)
      values (#local.section.generatedKey#, 'Housing', 1, 1, '#variables.ticketName#')
    ", {}, { datasource: variables.dsn.local });
    queryExecute("
      insert into option_item (SECTION, NAME, ITEM, CREATED_BY)
      values (#local.section.generatedKey#, 'Housing', #local.option_m.generatedKey#, '#variables.ticketName#')
    ", {}, { datasource: variables.dsn.local });
    queryExecute("
      insert into option_item (SECTION, NAME, ITEM, CREATED_BY)
      values (#local.section.generatedKey#, 'Housing', #local.option_f.generatedKey#, '#variables.ticketName#')
    ", {}, { datasource: variables.dsn.local });

    return { section: local.section.generatedKey, option_m: local.option_m.generatedKey, option_f: local.option_f.generatedKey };
  }

  // create pm_session
  public numeric function create_pm_session(required numeric section, required numeric option_m, required numeric option_f) {
    queryExecute("
      insert into pm_session (TITLE, PRODUCT, START_DATE, END_DATE, SESSION_TYPE, PM_LOCATION, PM_SELECTOR_SET_TEMPLATE, CREATED_BY)
      values ('#variables.ticketName# Test Session', :product, '2024-08-04', '2024-08-10', 'FSY', 2, #variables.pm_selector_set_template#, '#variables.ticketName#')
    ", {product: arguments.section}, { datasource: variables.dsn.local, result: "local.pm_session" });
    if (!local.pm_session.keyExists("generatedKey")) throw(type = "ds.error", message = "Failed to create pm_session", detail = serializeJSON(local.pm_session))

    queryExecute("
      insert into pm_selector_product (PM_SESSION, PM_SELECTOR, PRODUCT, CREATED_BY)
      values (#local.pm_session.generatedKey#, #variables.selector_m#, #arguments.option_m#, '#variables.ticketName#')
    ", {}, { datasource: variables.dsn.local });
    queryExecute("
      insert into pm_selector_product (PM_SESSION, PM_SELECTOR, PRODUCT, CREATED_BY)
      values (#local.pm_session.generatedKey#, #variables.selector_f#, #arguments.option_f#, '#variables.ticketName#')
    ", {}, { datasource: variables.dsn.local });

    return local.pm_session.generatedKey
  }

  // create pm_group and pm_counselor records
  public numeric function create_pm_group(required numeric pm_session_id, required numeric group_number, required string gender, numeric size = 4, numeric pm_selector = variables.selector_m) {
    queryExecute("
      insert into pm_group (PM_SESSION, GROUP_NUMBER, SIZE, CREATED_BY)
      values (#arguments.pm_session_id#, #arguments.group_number#, #arguments.size#, '#variables.ticketName#')
    ", {}, { datasource: variables.dsn.local, result: "local.pm_group" });
    if (!local.pm_group.keyExists("generatedKey")) throw(type = "ds.error", message = "Failed to create pm_group", detail = serializeJSON(local.pm_group))

    queryExecute("
      insert into pm_counselor (PM_SESSION, TYPE, NUMBER, GENDER, CREATED_BY)
      values (#arguments.pm_session_id#, 'Counselor', #arguments.group_number#, '#arguments.gender#', '#variables.ticketName#')
    ", {}, { datasource: variables.dsn.local, result: "local.pm_counselor" });
    if (!local.pm_counselor.keyExists("generatedKey")) throw(type = "ds.error", message = "Failed to create pm_counselor", detail = serializeJSON(local.pm_counselor))

    queryExecute("
      insert into pm_group_selector (PM_GROUP, PM_SELECTOR, CREATED_BY)
      values (#local.pm_group.generatedKey#, #arguments.pm_selector#, '#variables.ticketName#')
    ", {}, { datasource: variables.dsn.local, result: "local.pm_group_selector" });
    if (local.pm_group_selector.recordCount == 0) throw(type = "ds.error", message = "Failed to create pm_group_selector", detail = serializeJSON(local.pm_group_selector))

    // connect
    queryExecute("
      update pm_group set pm_counselor = #local.pm_counselor.generatedKey#, updated_by = '#variables.ticketName#'
      where pm_group_id = #local.pm_group.generatedKey#
    ", {}, { datasource: variables.dsn.local });

    return local.pm_group.generatedKey
  }

  // create participant people
  public numeric function create_person(required numeric lds_account_id, required string gender, string age = 15) {
    queryExecute("
      insert into person (FIRST_NAME, LAST_NAME, GENDER, BIRTHDATE, LDS_ACCOUNT_ID, CREATED_BY)
      values ('Firsty', 'Lasterson', '#arguments.gender#', '#2024 - arguments.age#-01-01', #arguments.lds_account_id#, '#variables.ticketName#')
    ", {}, { datasource: variables.dsn.local, result: "local.person" });
    if (!local.person.keyExists("generatedKey")) throw(type = "ds.error", message = "Failed to create person", detail = serializeJSON(local.person));

    return local.person.generatedKey;
  }

  // create participant contexts
  public numeric function create_context_program(required numeric personID, required numeric programID) {
    queryExecute("
      insert into context (PERSON, PRODUCT, CONTEXT_TYPE, STATUS)
      values (#arguments.personID#, #arguments.programID#, 'Program', 'Active')
    ", {}, { datasource: variables.dsn.local, result: "local.context" });
    if (!local.context.keyExists("generatedKey")) throw(type = "ds.error", message = "Failed to create program context", detail = serializeJSON(local.context));

    return local.context.generatedKey;
  }

  public numeric function create_context_section(required numeric personID, required numeric sectionID) {
    queryExecute("
      insert into context (PERSON, PRODUCT, CONTEXT_TYPE, STATUS, CREATED_BY)
      values (#arguments.personID#, #arguments.sectionID#, 'Enrollment', 'Active', '#variables.ticketName#')
    ", {}, { datasource: variables.dsn.local, result: "local.context" });
    if (!local.context.keyExists("generatedKey")) throw(type = "ds.error", message = "Failed to create section context", detail = serializeJSON(local.context));

    return local.context.generatedKey;
  }

  public numeric function create_context_option(required numeric personID, required numeric optionProductID, required numeric sectionContext) {
    queryExecute("
      insert into context (PERSON, PRODUCT, CONTEXT_TYPE, CHOICE_FOR, STATUS, CREATED_BY)
      values (#arguments.personID#, #arguments.optionProductID#, 'Enrollment', #arguments.sectionContext#, 'Active', '#variables.ticketName#')
    ", {}, { datasource: variables.dsn.local, result: "local.context" });
    if (!local.context.keyExists("generatedKey")) throw(type = "ds.error", message = "Failed to create option context", detail = serializeJSON(local.context));

    return local.context.generatedKey;
  }

  // create accommodations
  public numeric function create_accommodation(required numeric contextID, required string accommodationType) {
    queryExecute("
      insert into accommodation (CONTEXT, TYPE)
      values (#arguments.contextID#, '#arguments.accommodationType#')
    ", {}, { datasource: variables.dsn.local, result: "local.accommodation" });
    if (!local.accommodation.keyExists("generatedKey")) throw(type = "ds.error", message = "Failed to create accommodation", detail = serializeJSON(local.accommodation));

    return local.accommodation.generatedKey;
  }

  // create pm_housing
  public numeric function create_pm_housing(required numeric pm_session_id, string building = "BLDG_A", string room = "101", string bed = "A", string apartment) {
    queryExecute("
      insert into pm_housing (PM_SESSION, BUILDING, APARTMENT, ROOM, BED, CREATED_BY)
      values (#arguments.pm_session_id#, '#arguments.building#', :apartment, '#arguments.room#', '#arguments.bed#', '#variables.ticketName#')
    ", {
      apartment: {value: arguments.keyExists("apartment") ? arguments.apartment : "", null: !arguments.keyExists("apartment")}
    }, { datasource: variables.dsn.local, result: "local.pm_housing" });
    if (!local.pm_housing.keyExists("generatedKey")) throw(type = "ds.error", message = "Failed to create pm_housing", detail = serializeJSON(local.pm_housing));

    return local.pm_housing.generatedKey;
  }

  // place people in groups
  public void function assign_person_group(required numeric sectionContext, required numeric pm_group) {
    queryExecute("
      update context set pm_group = #arguments.pm_group#, updated_by = '#variables.ticketName#'
      where context_id = #arguments.sectionContext#
    ", {}, { datasource: variables.dsn.local });
  }

  // assign housing to groups
  public void function assign_housing_group(required numeric pm_housing_id, required numeric pm_group) {
    queryExecute("
      update pm_housing set pm_group = #arguments.pm_group#, updated_by = '#variables.ticketName#'
      where pm_housing_id = #arguments.pm_housing_id#
    ", {}, { datasource: variables.dsn.local });
  }

  // place people in beds (those that should be there prior to the test running to place the test user(s))
  public void function assign_person_housing(required numeric sectionContext, required numeric pm_housing_id) {
    queryExecute("
      update pm_housing set context = #arguments.sectionContext#, updated_by = '#variables.ticketName#'
      where pm_housing_id = #arguments.pm_housing_id#
    ", {}, { datasource: variables.dsn.local });
  }

  // TEST CASES
  /*
    run them like so, in scratch:

    ```
    hat = variables.injector.getInstance("housingAutoassignTester@ds")
    writedump(hat.test(1)) // number of test to run
    ```
  */

  // main test function

  public struct function test(required numeric test) {
    teardown()
    local.result = invoke("", "test_#arguments.test#")
    return { result: local?.result }
  }

  // utils

  public void function deleteRecord(required string table) {
    queryExecute("delete #arguments.table# where created_by = '#variables.ticketName#'", {}, { datasource: variables.dsn.local });
  }

  public struct function setup_session() {
    products = create_product_section()
    pm_session = create_pm_session(argumentCollection = products)
    pm_group_m = create_pm_group(pm_session, 1, "M")

    return {
      products: products,
      pm_session: pm_session,
      pm_group_m: pm_group_m
    }
  }

  public void function teardown() {
    // clean slate
    deleteRecord("pm_housing")
    deleteRecord("context")
    deleteRecord("person")
    deleteRecord("pm_group_selector")
    deleteRecord("pm_group")
    deleteRecord("pm_counselor")
    deleteRecord("pm_selector_product")
    deleteRecord("pm_session")
    deleteRecord("option_item")
    deleteRecord("option_group")
    deleteRecord("product")
  }

  // tests (but really, these are just data setup conveniences for testing the housing > people auto-assign button in the UI.  No asserts here or nuthin'.)

  // a male without a roommate is placed in an empty room
  public struct function test_1() {
    // session setup
    local.data = setup_session()
    local.pm_housing_id = create_pm_housing(local.data.pm_session)
    assign_housing_group(local.pm_housing_id, local.data.pm_group_m)
    // person/context setup
    local.person1 = create_person(1, "M")
    local.sectionContext = create_context_section(local.person1, local.data.products.section)
    local.optionContext = create_context_option(local.person1, local.data.products.option_m, local.sectionContext)
    assign_person_group(local.sectionContext, local.data.pm_group_m)

    return {
      products: local.data.products,
      pm_session: local.data.pm_session,
      pm_group_m: local.data.pm_group_m,
      person1: local.person1,
      sectionContext: local.sectionContext,
      optionContext: local.optionContext
    }
  }

  // A minor male participant with a minor male roommate should be placed together with the roommate in an empty room.
  public struct function test_2() {
    // session setup
    local.data = setup_session()
    local.pm_housing_id = create_pm_housing(local.data.pm_session)
    assign_housing_group(local.pm_housing_id, local.data.pm_group_m)
    // person/context setup
    local.person1 = create_person(1, "M")
    local.person2 = create_person(2, "M")
    local.sectionContext1 = create_context_section(local.person1, local.data.products.section)
    local.sectionContext2 = create_context_section(local.person2, local.data.products.section)
    local.optionContext1 = create_context_option(local.person1, local.data.products.option_m, local.sectionContext1)
    local.optionContext2 = create_context_option(local.person2, local.data.products.option_m, local.sectionContext2)
    assign_person_group(local.sectionContext1, local.data.pm_group_m)
    assign_person_group(local.sectionContext2, local.data.pm_group_m)

    return {
      products: local.data.products,
      pm_session: local.data.pm_session,
      pm_group_m: local.data.pm_group_m,
      person1: local.person1,
      person2: local.person2,
      sectionContext1: local.sectionContext1,
      sectionContext2: local.sectionContext2,
      optionContext1: local.optionContext1,
      optionContext2: local.optionContext2
    }
  }

  // A minor male participant with an adult male roommate should be placed together with the roommate in an empty room.
  public struct function test_3() {
    // session setup
    local.data = setup_session()
    local.pm_housing_id = create_pm_housing(local.data.pm_session)
    assign_housing_group(local.pm_housing_id, local.data.pm_group_m)
    // person/context setup
    local.person1 = create_person(1, "M", 15)
    local.person2 = create_person(2, "M", 18)
    local.sectionContext1 = create_context_section(local.person1, local.data.products.section)
    local.sectionContext2 = create_context_section(local.person2, local.data.products.section)
    local.optionContext1 = create_context_option(local.person1, local.data.products.option_m, local.sectionContext1)
    local.optionContext2 = create_context_option(local.person2, local.data.products.option_m, local.sectionContext2)
    assign_person_group(local.sectionContext1, local.data.pm_group_m)
    assign_person_group(local.sectionContext2, local.data.pm_group_m)

    return {
      products: local.data.products,
      pm_session: local.data.pm_session,
      pm_group_m: local.data.pm_group_m,
      person1: local.person1,
      person2: local.person2,
      sectionContext1: local.sectionContext1,
      sectionContext2: local.sectionContext2,
      optionContext1: local.optionContext1,
      optionContext2: local.optionContext2
    }
}

  // A male participant without a roommate should be placed in a room where another age-matching male is already placed.
  public struct function test_4() {
    // session setup
    local.data = setup_session()
    local.pm_housing_id = create_pm_housing(local.data.pm_session)
    assign_housing_group(local.pm_housing_id, local.data.pm_group_m)
    // person/context setup
    local.person1 = create_person(1, "M", 15)
    local.sectionContext1 = create_context_section(local.person1, local.data.products.section)
    local.optionContext1 = create_context_option(local.person1, local.data.products.option_m, local.sectionContext1)
    assign_person_group(local.sectionContext1, local.data.pm_group_m)
    local.person2 = create_person(2, "M", 15)
    local.sectionContext2 = create_context_section(local.person2, local.data.products.section)
    local.optionContext2 = create_context_option(local.person2, local.data.products.option_m, local.sectionContext2)
    assign_person_group(local.sectionContext2, local.data.pm_group_m)

    return {
      products: local.data.products,
      pm_session: local.data.pm_session,
      pm_group_m: local.data.pm_group_m,
      person1: local.person1,
      person2: local.person2,
      sectionContext1: local.sectionContext1,
      sectionContext2: local.sectionContext2,
      optionContext1: local.optionContext1,
      optionContext2: local.optionContext2
    }
  }

  // A male participant without a roommate should not be placed in a room where another age-non-matching male is already placed.
  public struct function test_5() {
    // session setup
    local.data = setup_session()
    local.pm_housing_id = create_pm_housing(local.data.pm_session)
    assign_housing_group(local.pm_housing_id, local.data.pm_group_m)
    // person/context setup
    local.person1 = create_person(1, "M", 15)
    local.sectionContext1 = create_context_section(local.person1, local.data.products.section)
    local.optionContext1 = create_context_option(local.person1, local.data.products.option_m, local.sectionContext1)
    assign_person_group(local.sectionContext1, local.data.pm_group_m)
    local.person2 = create_person(2, "M", 18)
    local.sectionContext2 = create_context_section(local.person2, local.data.products.section)
    local.optionContext2 = create_context_option(local.person2, local.data.products.option_m, local.sectionContext2)
    assign_person_group(local.sectionContext2, local.data.pm_group_m)

    return {
      products: local.data.products,
      pm_session: local.data.pm_session,
      pm_group_m: local.data.pm_group_m,
      person1: local.person1,
      person2: local.person2,
      sectionContext1: local.sectionContext1,
      sectionContext2: local.sectionContext2,
      optionContext1: local.optionContext1,
      optionContext2: local.optionContext2
    }
  }

  // A minor male participant with a minor male roommate should be placed together with the roommate in a room where another age-matching male is already placed.
  public struct function test_6() {
    // session setup
    local.data = setup_session()
    local.pm_housing_id = create_pm_housing(local.data.pm_session)
    assign_housing_group(local.pm_housing_id, local.data.pm_group_m)
    // person/context setup
    local.person1 = create_person(1, "M", 15)
    local.person2 = create_person(2, "M", 15)
    local.sectionContext1 = create_context_section(local.person1, local.data.products.section)
    local.sectionContext2 = create_context_section(local.person2, local.data.products.section)
    local.optionContext1 = create_context_option(local.person1, local.data.products.option_m, local.sectionContext1)
    local.optionContext2 = create_context_option(local.person2, local.data.products.option_m, local.sectionContext2)
    assign_person_group(local.sectionContext1, local.data.pm_group_m)
    assign_person_group(local.sectionContext2, local.data.pm_group_m)
    local.person3 = create_person(3, "M", 15)
    local.sectionContext3 = create_context_section(local.person3, local.data.products.section)
    local.optionContext3 = create_context_option(local.person3, local.data.products.option_m, local.sectionContext3)
    assign_person_group(local.sectionContext3, local.data.pm_group_m)

    return {
      products: local.data.products,
      pm_session: local.data.pm_session,
      pm_group_m: local.data.pm_group_m,
      person1: local.person1,
      person2: local.person2,
      person3: local.person3,
      sectionContext1: local.sectionContext1,
      sectionContext2: local.sectionContext2,
      sectionContext3: local.sectionContext3,
      optionContext1: local.optionContext1,
      optionContext2: local.optionContext2,
      optionContext3: local.optionContext3
    }
  }

  // A minor male participant with a minor male roommate should not be placed together with the roommate in a room where another age-non-matching male is already placed.
  public struct function test_7() {
    // session setup
    local.data = setup_session()
    local.pm_housing_id = create_pm_housing(local.data.pm_session)
    assign_housing_group(local.pm_housing_id, local.data.pm_group_m)
    // person/context setup
    local.person1 = create_person(1, "M", 15)
    local.person2 = create_person(2, "M", 15)
    local.sectionContext1 = create_context_section(local.person1, local.data.products.section)
    local.sectionContext2 = create_context_section(local.person2, local.data.products.section)
    local.optionContext1 = create_context_option(local.person1, local.data.products.option_m, local.sectionContext1)
    local.optionContext2 = create_context_option(local.person2, local.data.products.option_m, local.sectionContext2)
    assign_person_group(local.sectionContext1, local.data.pm_group_m)
    assign_person_group(local.sectionContext2, local.data.pm_group_m)
    local.person3 = create_person(3, "M", 18)
    local.sectionContext3 = create_context_section(local.person3, local.data.products.section)
    local.optionContext3 = create_context_option(local.person3, local.data.products.option_m, local.sectionContext3)
    assign_person_group(local.sectionContext3, local.data.pm_group_m)

    return {
      products: local.data.products,
      pm_session: local.data.pm_session,
      pm_group_m: local.data.pm_group_m,
      person1: local.person1,
      person2: local.person2,
      person3: local.person3,
      sectionContext1: local.sectionContext1,
      sectionContext2: local.sectionContext2,
      sectionContext3: local.sectionContext3,
      optionContext1: local.optionContext1,
      optionContext2: local.optionContext2,
      optionContext3: local.optionContext3
    }
  }

  // A male minor participant without a roommate should not be placed in a mixed room.
  public struct function test_8() {
    // session setup
    local.data = setup_session()
    local.pm_housing_id = create_pm_housing(local.data.pm_session)
    assign_housing_group(local.pm_housing_id, local.data.pm_group_m)
    // person/context setup
    local.person1 = create_person(1, "M", 15)
    local.person2 = create_person(2, "F", 15)
    local.sectionContext1 = create_context_section(local.person1, local.data.products.section)
    local.sectionContext2 = create_context_section(local.person2, local.data.products.section)
    local.optionContext1 = create_context_option(local.person1, local.data.products.option_m, local.sectionContext1)
    local.optionContext2 = create_context_option(local.person2, local.data.products.option_m, local.sectionContext2)
    assign_person_group(local.sectionContext1, local.data.pm_group_m)
    assign_person_group(local.sectionContext2, local.data.pm_group_m)
    local.person3 = create_person(3, "M", 15)
    local.sectionContext3 = create_context_section(local.person3, local.data.products.section)
    local.optionContext3 = create_context_option(local.person3, local.data.products.option_m, local.sectionContext3)
    assign_person_group(local.sectionContext3, local.data.pm_group_m)

    return {
      products: local.data.products,
      pm_session: local.data.pm_session,
      pm_group_m: local.data.pm_group_m,
      person1: local.person1,
      person2: local.person2,
      person3: local.person3,
      sectionContext1: local.sectionContext1,
      sectionContext2: local.sectionContext2,
      sectionContext3: local.sectionContext3,
      optionContext1: local.optionContext1,
      optionContext2: local.optionContext2,
      optionContext3: local.optionContext3
    }
  }

  // A male adult participant without a roommate should not be placed in a mixed room.
  public struct function test_9() {
    // session setup
    local.data = setup_session()
    local.pm_housing_id = create_pm_housing(local.data.pm_session)
    assign_housing_group(local.pm_housing_id, local.data.pm_group_m)
    // person/context setup
    local.person1 = create_person(1, "M", 15)
    local.person2 = create_person(2, "F", 15)
    local.sectionContext1 = create_context_section(local.person1, local.data.products.section)
    local.sectionContext2 = create_context_section(local.person2, local.data.products.section)
    local.optionContext1 = create_context_option(local.person1, local.data.products.option_m, local.sectionContext1)
    local.optionContext2 = create_context_option(local.person2, local.data.products.option_m, local.sectionContext2)
    assign_person_group(local.sectionContext1, local.data.pm_group_m)
    assign_person_group(local.sectionContext2, local.data.pm_group_m)
    local.person3 = create_person(3, "M", 18)
    local.sectionContext3 = create_context_section(local.person3, local.data.products.section)
    local.optionContext3 = create_context_option(local.person3, local.data.products.option_m, local.sectionContext3)
    assign_person_group(local.sectionContext3, local.data.pm_group_m)

    return {
      products: local.data.products,
      pm_session: local.data.pm_session,
      pm_group_m: local.data.pm_group_m,
      person1: local.person1,
      person2: local.person2,
      person3: local.person3,
      sectionContext1: local.sectionContext1,
      sectionContext2: local.sectionContext2,
      sectionContext3: local.sectionContext3,
      optionContext1: local.optionContext1,
      optionContext2: local.optionContext2,
      optionContext3: local.optionContext3
    }
  }

  // A minor male participant with a minor male roommate should not be placed in a mixed room.
  public struct function test_10() {
    // session setup
    local.data = setup_session()
    local.pm_housing_id = create_pm_housing(local.data.pm_session)
    assign_housing_group(local.pm_housing_id, local.data.pm_group_m)

    // person/context setup
    local.person1 = create_person(1, "M", 12)  // Minor male
    local.person2 = create_person(2, "M", 12)  // Minor male roommate
    local.sectionContext1 = create_context_section(local.person1, local.data.products.section)
    local.sectionContext2 = create_context_section(local.person2, local.data.products.section)
    local.optionContext1 = create_context_option(local.person1, local.data.products.option_m, local.sectionContext1)
    local.optionContext2 = create_context_option(local.person2, local.data.products.option_m, local.sectionContext2)
    assign_person_group(local.sectionContext1, local.data.pm_group_m)
    assign_person_group(local.sectionContext2, local.data.pm_group_m)

    // Ensure a mixed room is available
    local.mixed_room = create_room(local.data.products.mixed_room)

    // Link the persons as roommates
    link_roommates(local.person1, local.person2)

    return {
      products: local.data.products,
      pm_session: local.data.pm_session,
      pm_group_m: local.data.pm_group_m,
      person1: local.person1,
      person2: local.person2,
      sectionContext1: local.sectionContext1,
      sectionContext2: local.sectionContext2,
      optionContext1: local.optionContext1,
      optionContext2: local.optionContext2,
      mixed_room: local.mixed_room
    }
  }

  // A minor male participant with an adult male roommate should not be placed in a mixed room.
  public struct function test_11() {
    // session setup
    local.data = setup_session()
    local.pm_housing_id = create_pm_housing(local.data.pm_session)
    assign_housing_group(local.pm_housing_id, local.data.pm_group_m)

    // person/context setup
    local.person1 = create_person(1, "M", 12)  // Minor male
    local.person2 = create_person(2, "F", 18)  // Adult female roommate
    local.sectionContext1 = create_context_section(local.person1, local.data.products.section)
    local.sectionContext2 = create_context_section(local.person2, local.data.products.section)
    local.optionContext1 = create_context_option(local.person1, local.data.products.option_m, local.sectionContext1)
    local.optionContext2 = create_context_option(local.person2, local.data.products.option_m, local.sectionContext2)
    assign_person_group(local.sectionContext1, local.data.pm_group_m)
    assign_person_group(local.sectionContext2, local.data.pm_group_m)

    // Ensure a mixed room is available
    local.mixed_room = create_room(local.data.products.mixed_room)

    // Link the persons as roommates
    link_roommates(local.person1, local.person2)

    return {
      products: local.data.products,
      pm_session: local.data.pm_session,
      pm_group_m: local.data.pm_group_m,
      person1: local.person1,
      person2: local.person2,
      sectionContext1: local.sectionContext1,
      sectionContext2: local.sectionContext2,
      optionContext1: local.optionContext1,
      optionContext2: local.optionContext2,
      mixed_room: local.mixed_room
    }
  }

  // A minor male participant with an adult male roommate should not be placed in a room with a single male minor.
  public struct function test_12() {
    // session setup
    local.data = setup_session()
    local.pm_housing_id = create_pm_housing(local.data.pm_session)
    assign_housing_group(local.pm_housing_id, local.data.pm_group_m)

    // person/context setup
    local.person1 = create_person(1, "M", 12)  // Minor male
    local.person2 = create_person(2, "M", 18)  // Adult male roommate
    local.person3 = create_person(3, "M", 12)  // Single male minor in a room
    local.sectionContext1 = create_context_section(local.person1, local.data.products.section)
    local.sectionContext2 = create_context_section(local.person2, local.data.products.section)
    local.sectionContext3 = create_context_section(local.person3, local.data.products.section)
    local.optionContext1 = create_context_option(local.person1, local.data.products.option_m, local.sectionContext1)
    local.optionContext2 = create_context_option(local.person2, local.data.products.option_m, local.sectionContext2)
    local.optionContext3 = create_context_option(local.person3, local.data.products.option_m, local.sectionContext3)
    assign_person_group(local.sectionContext1, local.data.pm_group_m)
    assign_person_group(local.sectionContext2, local.data.pm_group_m)
    assign_person_group(local.sectionContext3, local.data.pm_group_m)

    // Ensure the room has at least two available beds
    local.room = create_room(local.data.products.mixed_room, 2)

    // Link the persons as roommates
    link_roommates(local.person1, local.person2)

    return {
      products: local.data.products,
      pm_session: local.data.pm_session,
      pm_group_m: local.data.pm_group_m,
      person1: local.person1,
      person2: local.person2,
      person3: local.person3,
      sectionContext1: local.sectionContext1,
      sectionContext2: local.sectionContext2,
      sectionContext3: local.sectionContext3,
      optionContext1: local.optionContext1,
      optionContext2: local.optionContext2,
      optionContext3: local.optionContext3,
      room: local.room
    }
  }

  // A minor male participant with an adult male roommate should not be placed in a room with a single male adult.
  public struct function test_13() {
    // session setup
    local.data = setup_session()
    local.pm_housing_id = create_pm_housing(local.data.pm_session)
    assign_housing_group(local.pm_housing_id, local.data.pm_group_m)

    // person/context setup
    local.person1 = create_person(1, "M", 12)  // Minor male
    local.person2 = create_person(2, "M", 18)  // Adult male roommate
    local.person3 = create_person(3, "M", 18)  // Single male adult in a room
    local.sectionContext1 = create_context_section(local.person1, local.data.products.section)
    local.sectionContext2 = create_context_section(local.person2, local.data.products.section)
    local.sectionContext3 = create_context_section(local.person3, local.data.products.section)
    local.optionContext1 = create_context_option(local.person1, local.data.products.option_m, local.sectionContext1)
    local.optionContext2 = create_context_option(local.person2, local.data.products.option_m, local.sectionContext2)
    local.optionContext3 = create_context_option(local.person3, local.data.products.option_m, local.sectionContext3)
    assign_person_group(local.sectionContext1, local.data.pm_group_m)
    assign_person_group(local.sectionContext2, local.data.pm_group_m)
    assign_person_group(local.sectionContext3, local.data.pm_group_m)

    // Ensure the room has at least two available beds
    local.room = create_room(local.data.products.mixed_room, 2)

    // Link the persons as roommates
    link_roommates(local.person1, local.person2)

    return {
      products: local.data.products,
      pm_session: local.data.pm_session,
      pm_group_m: local.data.pm_group_m,
      person1: local.person1,
      person2: local.person2,
      person3: local.person3,
      sectionContext1: local.sectionContext1,
      sectionContext2: local.sectionContext2,
      sectionContext3: local.sectionContext3,
      optionContext1: local.optionContext1,
      optionContext2: local.optionContext2,
      optionContext3: local.optionContext3,
      room: local.room
    }
  }

}
