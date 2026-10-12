FROM tomcat:10-jdk21
# Official Tomcat images ship the default webapps (incl. the ROOT welcome page) disabled in webapps.dist; re-enable them so / returns 200 instead of 404
RUN mv /usr/local/tomcat/webapps.dist/* /usr/local/tomcat/webapps/
# Application Insights Java auto-instrumentation agent - attaches via JVM flag, no source/app code needed.
# Bump the version below if you want a newer agent: https://github.com/microsoft/ApplicationInsights-Java/releases
ADD https://github.com/microsoft/ApplicationInsights-Java/releases/download/3.7.10/applicationinsights-agent-3.7.10.jar /agent/applicationinsights-agent.jar
ENV JAVA_TOOL_OPTIONS="-javaagent:/agent/applicationinsights-agent.jar"