package main.java.com.example.logmodifier;

import java.util.List;
import java.util.Arrays;
import com.intuit.karate.http.HttpLogModifier;

public class LogModifier implements HttpLogModifier {

    private static final List<String> SENSITIVE_KEYWORDS = Arrays.asList(
            "authorization", "auth", "token", "password", "secret", "key", "bearer", "x-api-key");

    private String maskByCheckingValue(String value) {

        if (value == null) {
            return value;
        }

        String modifiedValue = value;

        // Mask Authorization headers
        modifiedValue = modifiedValue.replaceAll(
                "(?i)(authorization|auth)\\s*:\\s*[^\\s,}]+",
                "$1: ***MASKED***");

        // Mask bearer tokens
        modifiedValue = modifiedValue.replaceAll(
                "(?i)bearer\\s+[^\\s,}]+",
                "bearer ***MASKED***");

        // Mask API keys and secrets in headers
        for (String keyword : SENSITIVE_KEYWORDS) {
            modifiedValue = modifiedValue.replaceAll(
                    "(?i)([\"']?" + keyword + "[\"']?\\s*[:=]\\s*[\"']?)[^\"'\\s,}\\]]+([\"']?)",
                    "$1***MASKED***$2");
        }

        // Mask JSON formatted auth parameters
        modifiedValue = modifiedValue.replaceAll(
                "(?i)([\"'](?:authorization|auth|token|password|secret|key|bearer|x-api-key)[\"']\\s*:\\s*[\"'])([^\"']+)([\"'])",
                "$1***MASKED***$3");

        // Mask query parameters
        modifiedValue = modifiedValue.replaceAll(
                "(?i)([?&](?:auth|token|key|secret|authorization)=)[^&\\s]+",
                "$1***MASKED***");

        return modifiedValue;

    }

    private String maskByCheckingKey(String key, String value) {

        for (String keyword : SENSITIVE_KEYWORDS) {
            if (key.toLowerCase().contains(keyword)) {
                return "***MASKED***";
            }
        }

        return value;

    }

    @Override
    public String uri(String uri) {
        return maskByCheckingValue(uri);
    }

    @Override
    public String header(String name, String value) {
        String maskedValue = maskByCheckingKey(name, value);
        maskedValue = maskByCheckingValue(maskedValue);
        return maskedValue;
    }

    @Override
    public String request(String uri, String request) {
        return maskByCheckingValue(request);
    }

    @Override
    public String response(String uri, String response) {
        return maskByCheckingValue(response);
    }

    @Override
    public boolean enableForUri(String uri) {
        return true;
    }
}