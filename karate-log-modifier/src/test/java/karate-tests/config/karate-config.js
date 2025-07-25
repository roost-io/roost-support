function fn() {
  // MUST define these variables first!
  var System = Java.type("java.lang.System");
  var out = System.out;
  var err = System.err;
  out.println("==========================================");
  out.println("KARATE CONFIG FUNCTION STARTED");
  out.println("==========================================");
  function maskSensitiveFields(obj) {
    var sensitiveKeys = ["password", "token", "authorization"];
    for (var key in obj) {
      if (sensitiveKeys.includes(key.toLowerCase())) {
        obj[key] = "******";
      } else if (typeof obj[key] === "object" && obj[key] !== null) {
        maskSensitiveFields(obj[key]);
      }
    }
    return obj;
  }
  const envVars = {};
  // Get all environment variables from the OS
  const env = System.getenv();
  const keys = env.keySet().toArray();
  out.println("CONFIG: Processing " + keys.length + " environment variables");
  for (let i = 0; i < keys.length; i++) {
    const key = keys[i];
    envVars[key] = env.get(key);
    if (
      key != "API_TEST_SERVER_CONFIG" &&
      (key.includes("API_HOST") ||
        key.includes("BASE_URL") ||
        key.includes("URL_BASE"))
    ) {
      out.println("CONFIG: Set envVar " + key + " = " + env.get(key));
    }
  }
  // Add Karate's own env variable
  envVars["karate.env"] = karate.env;
  const config = {
    maskSensitiveFields: maskSensitiveFields,
    karate: {
      properties: {
        ...envVars,
      },
    },
  };
  // Configure log modifier globally with error handling
  try {
    out.println("CONFIG: Attempting to load LogModifier class...");
    const LM = Java.type("com.example.logmodifier.LogModifier");
    out.println("CONFIG: LogModifier class loaded successfully");
    out.println("CONFIG: Creating LogModifier instance...");
    const logModifierInstance = new LM();
    out.println("CONFIG: LogModifier instance created: " + logModifierInstance);
    out.println("CONFIG: Configuring karate with logModifier...");
    karate.configure("logModifier", logModifierInstance);
    out.println("CONFIG: LogModifier configured successfully!");
  } catch (e) {
    err.println("CONFIG ERROR: Failed to configure LogModifier: " + e);
    err.println("CONFIG ERROR: Exception details: " + e.message);
  }
  out.println("==========================================");
  out.println("KARATE CONFIG FUNCTION COMPLETED");
  out.println("==========================================");
  return config;
}
