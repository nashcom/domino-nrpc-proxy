
        # Error page configuration to include for HTTP configurations

        proxy_intercept_errors on;
        error_page 502 503 504 /error_page_service_not_available.html;
        error_page 404 /error_page_not_found.html;

        location = /error_page_service_not_available.html
        {
            internal;
            default_type text/html;
            alias /cfg/error_page_service_not_available.html;
        }

        location = /error_page_not_found.html
        {
            internal;
            default_type text/html;
            alias /cfg/error_page_not_found.html;
        }

