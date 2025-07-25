function fn() {
    function maskSensitiveFields(obj) {
        var sensitiveKeys = ['password', 'token', 'authorization'];
        for (var key in obj) {
            if (sensitiveKeys.includes(key.toLowerCase())) {
                obj[key] = '******';
            } else if (typeof obj[key] === 'object' && obj[key] !== null) {
                maskSensitiveFields(obj[key]);
            }
        }
        return obj;
    }
    const envVars = {};
    // Get all environment variables from the OS
    const System = Java.type('java.lang.System');
    const env = System.getenv();
    // karate.log('env is:', env);
    const keys = env.keySet().toArray();
    for (let i = 0; i < keys.length; i++) {
        const key = keys[i];
        envVars[key] = env.get(key);
        if (key != 'API_TEST_SERVER_CONFIG' &&
            (key.includes('API_HOST') || key.includes('BASE_URL') || key.includes('URL_BASE'))
        ) {
            karate.log('set envVars for key:', key, ' with ', env.get(key));
        }
    }
    // Add Karate's own env variable
    envVars['karate.env'] = karate.env;
    const config = {
        maskSensitiveFields: maskSensitiveFields,
        karate: {
            properties: {
                ...envVars,
                //additionalProperty: 'value'
            },
        }
    };

    // Configure log modifier globally
    const LM = Java.type("modifier.LogModifier");
    karate.configure('logModifier', new LM());

    // karate.log('Karate configuration:', config);
    return config;
}
