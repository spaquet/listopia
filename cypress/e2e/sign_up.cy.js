describe('Listopia - Sign Up Page', () => {
  beforeEach(() => {
    cy.visit('/sign_up');
  });

  it('should load the sign up page with correct heading', () => {
    cy.contains('Create your account').should('be.visible');
    cy.contains('Start organizing your life with Listopia').should(
      'be.visible'
    );
  });

  it('should display all required form fields', () => {
    cy.get('#user_name').should('exist');
    cy.get('#user_email').should('exist');
    cy.get('#user_password').should('exist');
    cy.get('#user_password_confirmation').should('exist');
    cy.get('input[type="submit"]').should('have.value', 'Create Account');
  });

  it('should show error for missing fields when submitting empty form', () => {
    cy.get('form').submit();
    cy.get('#user_name:invalid').should('exist');
    cy.get('#user_email:invalid').should('exist');
    cy.get('#user_password:invalid').should('exist');
    cy.get('#user_password_confirmation:invalid').should('exist');
  });

  it('should show validation error if passwords do not match', () => {
    cy.get('#user_name').type('Test User');
    cy.get('#user_email').type('testuser@example.com');
    cy.get('#user_password').type('password123');
    cy.get('#user_password_confirmation').type('wrongpassword');
    cy.get('form').submit();

    cy.get('div.bg-red-50').should(
      'contain',
      "Password confirmation doesn't match Password"
    );
  });

  it('should create a new account successfully', () => {
    const randomEmail = `user_${Date.now()}@example.com`;

    cy.get('#user_name').type('Test Cypress User');
    cy.get('#user_email').type(randomEmail);
    cy.get('#user_password').type('password123');
    cy.get('#user_password_confirmation').type('password123');
    cy.get('input[type="submit"]').click();

    // Assert flash message about email confirmation
    cy.get('#flash-messages').should('contain', 'Please check your email');
  });

  it('should redirect to sign in page when clicking "Sign in here"', () => {
    cy.contains('Sign in here').click();
    cy.url().should('include', '/sign_in');
  });
});
