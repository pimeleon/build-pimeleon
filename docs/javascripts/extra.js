// Custom JavaScript for Pi Router Documentation

document.addEventListener('DOMContentLoaded', function() {
    // Add copy button feedback
    document.querySelectorAll('button[data-clipboard-text]').forEach(function(button) {
        button.addEventListener('click', function() {
            const originalText = button.innerHTML;
            button.innerHTML = 'Copied!';
            setTimeout(function() {
                button.innerHTML = originalText;
            }, 2000);
        });
    });

    // Smooth scroll for anchor links
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            const href = this.getAttribute('href');
            if (href !== '#') {
                e.preventDefault();
                const target = document.querySelector(href);
                if (target) {
                    target.scrollIntoView({
                        behavior: 'smooth',
                        block: 'start'
                    });
                }
            }
        });
    });

    // Add external link icons
    document.querySelectorAll('a[href^="http"]').forEach(function(link) {
        if (!link.hostname.includes('pimeleon.com') && !link.hostname.includes('localhost')) {
            link.setAttribute('target', '_blank');
            link.setAttribute('rel', 'noopener noreferrer');
        }
    });

    // Table of contents highlighting
    const observer = new IntersectionObserver(entries => {
        entries.forEach(entry => {
            const id = entry.target.getAttribute('id');
            if (entry.intersectionRatio > 0) {
                document.querySelector(`nav li a[href="#${id}"]`)?.parentElement.classList.add('active');
            } else {
                document.querySelector(`nav li a[href="#${id}"]`)?.parentElement.classList.remove('active');
            }
        });
    });

    // Track all sections with IDs
    document.querySelectorAll('section[id], h2[id], h3[id]').forEach((section) => {
        observer.observe(section);
    });
});
